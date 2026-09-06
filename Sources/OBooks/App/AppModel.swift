import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var books: [BookSummary]
    @Published var selectedBookID: UUID?
    @Published var openBook: BookSummary?
    @Published var alert: AppAlert?

    private(set) var libraryStore: LibraryStore
    let readingStats: ReadingStatsLedger
    let speechPlaybackOwner = SpeechPlaybackOwner()
    let sync: SyncCoordinator
    let workspace: LibraryWorkspace?
    @Published private(set) var copyStatus: String?
    private var readingStatsStore: ReadingStatsStore
    private var readingStatsTracker: ReadingStatsTracker!
    private let logger = Logger(subsystem: "com.obooks.app", category: "app")
    private var readerWindows: [UUID: NSWindow] = [:]
    private var readerDelegates: [UUID: ReaderWindowDelegate] = [:]
    private var progressSaveTask: Task<Void, Never>?
    private var terminationObservation: NSObjectProtocol?

    init(rootURL: URL? = nil, credentials: (any SyncCredentialStorage)? = nil, observeLifecycle: Bool = true) {
        let workspace: LibraryWorkspace?
        let store: LibraryStore
        if let rootURL {
            workspace = nil
            store = LibraryStore(rootURL: rootURL)
        } else if let opened = try? LibraryWorkspace.openDefault() {
            workspace = opened
            store = LibraryStore(rootURL: opened.activeRoot)
        } else {
            workspace = nil
            store = LibraryStore()
        }
        let statsStore = ReadingStatsStore(rootURL: store.rootURL)
        let ledger = ReadingStatsLedger()
        ledger.replaceEvents(statsStore.loadEvents())
        self.workspace = workspace
        libraryStore = store
        readingStatsStore = statsStore
        readingStats = ledger
        books = store.load()
        sync = SyncCoordinator(rootURL: store.rootURL, credentials: credentials ?? SyncCredentialStore(rootURL: store.rootURL))
        readingStatsTracker = ReadingStatsTracker(ledger: ledger) { [weak self] in
            guard let self else { return }
            self.sync.localDataChanged()
            self.readingStatsStore.saveEvents(self.readingStats.events)
        }
        sync.attach(to: self, observeLifecycle: observeLifecycle)
        guard observeLifecycle else { return }
        terminationObservation = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.readingStatsTracker.flush()
                self.sync.localDataChanged()
                self.libraryStore.save(self.books)
            }
        }
    }

    deinit {
        if let terminationObservation { NotificationCenter.default.removeObserver(terminationObservation) }
    }

    func importEPUB() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.epub]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.message = "选择要导入的 EPUB 文件"

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            importEPUB(at: url)
        }
    }

    func importEPUB(at url: URL) {
        Task { @MainActor in
          do {
            let store = libraryStore
            var book = try await Task.detached(priority: .userInitiated) { try EPUBImporter(store: store).importBook(from: url) }.value
            if let existing = books.first(where: { $0.canonicalID == book.canonicalID && book.canonicalID != nil }) {
                if !store.isDownloaded(existing) {
                    try FileManager.default.moveItem(at: book.folderURL, to: existing.folderURL)
                    try store.preserveArchive(store.archiveURL(for: book), for: existing)
                }
                try store.deleteBookData(for: book)
                book = existing
            }
            books.removeAll { $0.id == book.id }
            books.append(book)
            books.sort { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
            persistLibrary()
            selectedBookID = book.id
            openReader(book)
            logger.info("导入完成: title=\(book.title, privacy: .public)")
        } catch {
            logger.error("导入失败: file=\(url.lastPathComponent, privacy: .public), error=\(error.localizedDescription, privacy: .public)")
            alert = AppAlert(title: "导入失败", message: error.localizedDescription)
          }
        }
    }

    func delete(_ book: BookSummary) {
        guard books.contains(where: { $0.id == book.id }) else {
            return
        }

        do {
            readingStatsTracker.stop(bookID: book.id)
            try sync.deleteBook(book)
        } catch {
            logger.error("删除失败: title=\(book.title, privacy: .public), error=\(error.localizedDescription, privacy: .public)")
            alert = AppAlert(title: "删除失败", message: error.localizedDescription)
            return
        }

        progressSaveTask?.cancel()
        closeReader(for: book.id)
        readingStats.removeBook(book.id)
        readingStatsStore.saveEvents(readingStats.events)
        books.removeAll { $0.id == book.id }
        if selectedBookID == book.id {
            selectedBookID = nil
        }
        if openBook?.id == book.id {
            openBook = nil
        }
        persistLibrary()
        do { try libraryStore.deleteBookData(for: book) }
        catch { alert = AppAlert(title: "文件清理失败", message: error.localizedDescription) }
        logger.info("删除完成: title=\(book.title, privacy: .public)")
    }

    func openSelectedBook() {
        guard let selectedBookID,
              let book = books.first(where: { $0.id == selectedBookID }) else {
            return
        }
        openReader(book)
    }

    func open(_ book: BookSummary) {
        selectedBookID = book.id
        openReader(book)
    }

    func openReader(_ book: BookSummary) {
        guard libraryStore.isDownloaded(book) else {
            Task { @MainActor in
                if await sync.download(book), let current = books.first(where: { $0.id == book.id }) {
                    openReader(current)
                } else if let error = sync.lastError {
                    alert = AppAlert(title: "下载失败", message: error)
                }
            }
            return
        }
        if let window = readerWindows[book.id] {
            updateLastOpened(book.id)
            AppWindowConfiguration.applyPrimaryStageBehavior(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let reader = ReaderView(book: book)
            .environmentObject(self)
        let hostingController = NSHostingController(rootView: reader)
        hostingController.sizingOptions = [.minSize]

        let initialSize = AppWindowConfiguration.readerWindowSize
        let window = ReaderWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = book.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = AppWindowConfiguration.readerWindowBackgroundColor()
        window.contentViewController = hostingController
        window.setContentSize(initialSize)
        AppWindowConfiguration.applyPrimaryStageBehavior(window)
        AppWindowConfiguration.centerOnScreen(window)
        let delegate = ReaderWindowDelegate(
            onClose: { [weak self] closingWindow in
                guard let self, self.readerWindows[book.id] === closingWindow else { return }
                let retainedWindow = self.readerWindows[book.id]
                let retainedDelegate = self.readerDelegates[book.id]
                closingWindow.delegate = nil
                self.readerWindows.removeValue(forKey: book.id)
                self.readerDelegates.removeValue(forKey: book.id)
                self.readingStatsTracker.stop(bookID: book.id)
                self.persistLibrary()
                withExtendedLifetime((retainedWindow, retainedDelegate)) {}
            },
            onReadingActiveChange: { [weak self] isActive in
                self?.readingStatsTracker.setActive(bookID: book.id, isActive: isActive)
            }
        )
        window.delegate = delegate
        readerDelegates[book.id] = delegate
        readerWindows[book.id] = window
        window.makeKeyAndOrderFront(nil)
        AppWindowConfiguration.centerOnScreen(window)
        NSApp.activate(ignoringOtherApps: true)
        updateLastOpened(book.id)
        logger.info("打开阅读窗口: title=\(book.title, privacy: .public)")
    }

    private func closeReader(for bookID: UUID) {
        readingStatsTracker.stop(bookID: bookID)
        if let window = readerWindows[bookID] {
            window.delegate = nil
            window.close()
        }
        readerWindows.removeValue(forKey: bookID)
        readerDelegates.removeValue(forKey: bookID)
    }

    func updateProgress(bookID: UUID, fraction: Double, position: ReadingPosition? = nil) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else {
            return
        }
        let normalized = min(max(fraction, 0), 1)
        let progressChanged = abs(books[index].progressFraction - normalized) > 0.005
        let positionChanged = position != nil && books[index].readingPosition != position
        guard progressChanged || positionChanged else {
            return
        }
        if progressChanged {
            books[index].progressFraction = normalized
        }
        if let position {
            books[index].readingPosition = position
        }
        books[index].lastOpenedAt = sync.now
        books[index].progressModifiedAt = sync.now
        readingStatsTracker.noteInteraction()
        sync.localDataChanged()
        scheduleProgressSave()
    }

    func toggleBookmark(bookID: UUID, position: ReadingPosition, title: String, progressFraction: Double) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].toggleBookmark(at: position, title: title, progressFraction: progressFraction)
        if let bookmarkIndex = books[index].bookmarks.firstIndex(where: { $0.matches(position) }) {
            books[index].bookmarks[bookmarkIndex].modifiedAt = sync.now
        }
        persistLibrary()
        logger.info("更新书签: book=\(bookID), count=\(self.books[index].bookmarks.count)")
    }

    func removeBookmark(bookID: UUID, bookmarkID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].bookmarks.removeAll { $0.id == bookmarkID }
        persistLibrary()
        logger.info("移除书签: book=\(bookID), bookmark=\(bookmarkID)")
    }

    func updateAnnotations(bookID: UUID, annotations: [ReaderAnnotation]) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let original = books[index].annotations
        books[index].annotations = annotations.map { value in
            var annotation = value
            if original.first(where: { $0.id == value.id }) != value { annotation.modifiedAt = sync.now }
            return annotation
        }
        persistLibrary()
        logger.info("更新高亮和笔记: book=\(bookID), count=\(annotations.count)")
    }

    func toggleFinished(for bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else {
            return
        }
        books[index].isFinished.toggle()
        books[index].metadataModifiedAt = sync.now
        let book = books[index]
        persistLibrary()
        logger.info("更新阅读完成状态: title=\(book.title, privacy: .public), finished=\(book.isFinished, privacy: .public)")
    }

    func removeFromContinueReading(for bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else {
            return
        }
        books[index].isHiddenFromContinueReading = true
        books[index].metadataModifiedAt = sync.now
        persistLibrary()
        logger.info("从继续阅读中移除: book=\(bookID)")
    }

    private func scheduleProgressSave() {
        progressSaveTask?.cancel()
        progressSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.persistLibrary()
        }
    }

    private func updateLastOpened(_ bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else {
            return
        }
        books[index].lastOpenedAt = sync.now
        books[index].progressModifiedAt = sync.now
        books[index].isHiddenFromContinueReading = false
        books[index].metadataModifiedAt = sync.now
        persistLibrary()
    }

    private func persistLibrary() {
        sync.localDataChanged()
        if !libraryStore.save(books) { alert = AppAlert(title: "保存失败", message: "无法保存本地书库") }
    }

    func assignCanonicalID(_ canonicalID: String, to bookID: UUID) throws {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].canonicalID = canonicalID
        guard libraryStore.save(books) else { throw CloudSyncError.message("保存图书身份失败") }
    }

    func mergeDuplicateBooks() throws {
        let groups = Dictionary(grouping: books.filter { $0.canonicalID != nil }, by: { $0.canonicalID! })
        var events = readingStats.events
        var discarded: [BookSummary] = []
        for duplicates in groups.values where duplicates.count > 1 {
            let ordered = duplicates.sorted {
                $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt < $1.importedAt
            }
            var kept = ordered[0]
            var bookmarkIDs = Set(kept.bookmarks.map(\.id))
            var annotationIDs = Set(kept.annotations.map(\.id))
            for book in ordered.dropFirst() {
                kept.bookmarks += book.bookmarks.filter { bookmarkIDs.insert($0.id).inserted }
                kept.annotations += book.annotations.filter { annotationIDs.insert($0.id).inserted }
                if (book.progressModifiedAt ?? book.lastOpenedAt ?? .distantPast) > (kept.progressModifiedAt ?? kept.lastOpenedAt ?? .distantPast) {
                    kept.progressFraction = book.progressFraction
                    kept.readingPosition = book.readingPosition
                    kept.lastOpenedAt = book.lastOpenedAt
                    kept.progressModifiedAt = book.progressModifiedAt
                }
                if !libraryStore.isDownloaded(kept), libraryStore.isDownloaded(book) {
                    try FileManager.default.moveItem(at: book.folderURL, to: kept.folderURL)
                }
                for index in events.indices where events[index].bookID == book.id { events[index].bookID = kept.id }
                closeReader(for: book.id)
                discarded.append(book)
            }
            books.removeAll { book in ordered.contains(where: { $0.id == book.id }) }
            books.append(kept)
        }
        guard !discarded.isEmpty else { return }
        readingStats.replaceEvents(events)
        guard libraryStore.save(books), readingStatsStore.saveEvents(events) else { throw CloudSyncError.message("合并重复图书失败") }
        for book in discarded { try libraryStore.deleteBookData(for: book) }
    }

    func applySyncedLibrary(books replacement: [BookSummary], events: [ReadingEvent], removed: [BookSummary]) throws {
        for book in removed {
            closeReader(for: book.id)
            try libraryStore.deleteBookData(for: book)
            if selectedBookID == book.id { selectedBookID = nil }
            if openBook?.id == book.id { openBook = nil }
        }
        books = replacement.map { original in
            var book = original
            book.storageRoot = libraryStore.rootURL
            return book
        }
        readingStats.replaceEvents(events)
        guard libraryStore.save(books), readingStatsStore.saveEvents(events) else {
            throw CloudSyncError.message("无法保存同步结果")
        }
    }

    var localCopySources: [LibraryProfile] {
        workspace?.sources(excluding: workspace?.activeID ?? "") ?? []
    }

    func loginToAccount(server: String, username: String, password: String) async {
        do {
            let url = try SyncAPI.validateServer(server)
            try persistCurrentProfile()
            if let workspace {
                let profile = try workspace.ensureAccountProfile(server: url, username: username)
                if profile.id != workspace.activeID {
                    try switchProfile(to: profile.id)
                }
            }
            await sync.login(server: server, username: username, password: password)
            if let workspace, let account = sync.account {
                try workspace.updateUserID(account.userID, for: workspace.activeID)
            }
        } catch {
            alert = AppAlert(title: "登录失败", message: error.localizedDescription)
        }
    }

    func copyFromLocalProfile(_ profile: LibraryProfile) {
        guard let workspace else { return }
        Task { @MainActor in
            do {
                persistLibrary()
                var destBooks = books
                var destEvents = readingStats.events
                let result = try await LibraryCopy.merge(
                    from: workspace.root(for: profile.id),
                    into: libraryStore,
                    destBooks: &destBooks,
                    destEvents: &destEvents
                ) { [weak self] message in
                    self?.copyStatus = message
                }
                books = destBooks
                readingStats.replaceEvents(destEvents)
                persistLibrary()
                copyStatus = nil
                logger.info("已从 \(profile.title, privacy: .public) 复制: added=\(result.added), merged=\(result.merged)")
            } catch {
                copyStatus = nil
                logger.error("复制书库失败: \(error.localizedDescription, privacy: .public)")
                alert = AppAlert(title: "复制失败", message: error.localizedDescription)
            }
        }
    }

    private func persistCurrentProfile() throws {
        progressSaveTask?.cancel()
        readingStatsTracker.flush()
        sync.localDataChanged()
        guard libraryStore.save(books), readingStatsStore.saveEvents(readingStats.events) else {
            throw CloudSyncError.message("无法保存当前书库")
        }
    }

    private func switchProfile(to profileID: String) throws {
        guard let workspace else { throw CloudSyncError.message("当前运行没有书库工作区") }
        for id in Array(readerWindows.keys) { closeReader(for: id) }
        selectedBookID = nil
        openBook = nil
        try workspace.setActive(profileID)
        libraryStore = LibraryStore(rootURL: workspace.activeRoot)
        readingStatsStore = ReadingStatsStore(rootURL: workspace.activeRoot)
        books = libraryStore.load()
        readingStats.replaceEvents(readingStatsStore.loadEvents())
        sync.rebind(rootURL: workspace.activeRoot)
        objectWillChange.send()
    }
}
