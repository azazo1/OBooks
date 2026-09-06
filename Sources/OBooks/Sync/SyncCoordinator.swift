import AppKit
import Combine
import Foundation
import Network
import OSLog

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var status = "未登录"
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var transferProgress: Double?
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var downloading: Set<UUID> = []
    @Published var deviceName: String

    private(set) var journal: SyncJournal
    private var journalStore: SyncJournalStore
    private var credentials: any SyncCredentialStorage
    private let logger = Logger(subsystem: "com.obooks.app", category: "sync")
    private weak var model: AppModel?
    private var api: SyncAPI?
    private var scheduled: Task<Void, Never>?
    private var retryDelay: TimeInterval = 2
    private var observations: [NSObjectProtocol] = []
    private var monitor: NWPathMonitor?
    private var storageFailed = false
    private var automaticSync = true
    private var observingLifecycle = false
    private var clockAnchor: (serverTime: TimeInterval, uptime: TimeInterval)?

    var account: SyncAccount? { journal.account }
    var now: Date {
        if let clockAnchor {
            return Date(timeIntervalSince1970: clockAnchor.serverTime + ProcessInfo.processInfo.systemUptime - clockAnchor.uptime)
        }
        return Date().addingTimeInterval(journal.clockOffset)
    }

    init(rootURL: URL, credentials: any SyncCredentialStorage) {
        journalStore = SyncJournalStore(rootURL: rootURL)
        self.credentials = credentials
        do { journal = try journalStore.load() }
        catch { journal = SyncJournal(); storageFailed = true; lastError = error.localizedDescription }
        deviceName = journal.deviceName
        lastSyncedAt = journal.lastSyncedAt
        pendingCount = journal.pending.count
    }

    deinit {
        scheduled?.cancel()
        monitor?.cancel()
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
    }

    func attach(to model: AppModel, observeLifecycle: Bool = true) {
        self.model = model
        automaticSync = observeLifecycle
        guard !storageFailed, model.libraryStore.loadError == nil else { return }
        do { try applyRemote() } catch { storageFailed = true; report(error); return }
        if let account = journal.account {
            do {
                isSignedIn = try credentials.read() != nil
                if isSignedIn { configureAPI(account.server) }
            } catch { report(error) }
        }
        guard observeLifecycle, !observingLifecycle else { return }
        observingLifecycle = true
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule(delay: 0) }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.schedule(delay: 0) } }
        }
        monitor.start(queue: DispatchQueue(label: "com.obooks.sync.network"))
        self.monitor = monitor
        schedule(delay: 0)
    }

    func rebind(rootURL: URL) {
        scheduled?.cancel()
        scheduled = nil
        api = nil
        isSignedIn = false
        isSyncing = false
        downloading = []
        transferProgress = nil
        lastError = nil
        storageFailed = false
        clockAnchor = nil
        retryDelay = 2
        journalStore = SyncJournalStore(rootURL: rootURL)
        credentials = SyncCredentialStore(rootURL: rootURL)
        do { journal = try journalStore.load() }
        catch { journal = SyncJournal(); storageFailed = true; lastError = error.localizedDescription }
        deviceName = journal.deviceName
        lastSyncedAt = journal.lastSyncedAt
        pendingCount = journal.pending.count
        if let account = journal.account {
            do {
                isSignedIn = try credentials.read() != nil
                if isSignedIn { configureAPI(account.server) }
            } catch { report(error) }
        } else {
            status = "未登录"
        }
        if let model, !storageFailed, model.libraryStore.loadError == nil {
            do { try applyRemote() } catch { storageFailed = true; report(error) }
        }
        if isSignedIn { schedule(delay: 0) }
    }

    func retainError(_ message: String, status: String) {
        lastError = message
        self.status = status
    }

    func login(server: String, username: String, password: String) async {
        guard !storageFailed, !isSyncing, downloading.isEmpty else { return }
        do {
            let url = try SyncAPI.validateServer(server)
            if let account = journal.account, account.server != url || account.username != username {
                throw CloudSyncError.message("当前书库已绑定其他账号, 请先切换账号")
            }
            isSyncing = true
            status = "正在登录"
            if let model {
                try await prepareLocalBooks(model)
                SyncProjection.capture(books: model.books, events: model.readingStats.events, journal: &journal, now: now)
                try persist()
            }
            configureAPI(url)
            guard let api else { return }
            let tokens = try await api.login(username: username, password: password, deviceID: journal.deviceID, deviceName: deviceName)
            if let account = journal.account, account.userID != tokens.userID {
                try? await api.logout()
                throw CloudSyncError.message("服务端账号身份已改变, 无法自动合并本地书库")
            }
            journal.account = SyncAccount(server: url, username: username, userID: tokens.userID)
            journal.deviceName = deviceName
            try persist()
            isSignedIn = true
            isSyncing = false
            await synchronize()
        } catch { isSyncing = false; report(error) }
    }

    func logout() async {
        scheduled?.cancel()
        scheduled = nil
        if let api {
            do {
                try await api.logout()
            } catch {
                logger.error("未能撤销服务端会话: \(error.localizedDescription, privacy: .public)")
                try? credentials.remove()
            }
        } else {
            try? credentials.remove()
        }
        api = nil
        isSignedIn = false
        isSyncing = false
        transferProgress = nil
        status = "未登录"
        lastError = nil
    }

    func localDataChanged() {
        guard !storageFailed, let model else { return }
        SyncProjection.capture(books: model.books, events: model.readingStats.events, journal: &journal, now: now)
        do { try persist(); schedule() } catch { report(error) }
    }

    func deleteBook(_ book: BookSummary) throws {
        guard !storageFailed else { throw CloudSyncError.message("同步数据损坏, 删除操作已暂停") }
        if let id = book.canonicalID {
            journal.enqueue(entity: "book", entityID: id, bookID: id, payload: SyncPayload(), modifiedAt: now, deleted: true)
            journal.uploadedContent.remove(id)
            journal.uploadedCovers.remove(id)
            try persist()
        }
    }

    func schedule(delay: TimeInterval = 1) {
        guard isSignedIn, !storageFailed, automaticSync else { return }
        scheduled?.cancel()
        scheduled = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.scheduled = nil
            await self?.synchronize()
        }
    }

    func synchronize() async {
        guard !isSyncing, !storageFailed, isSignedIn, let api, let model else { return }
        isSyncing = true
        lastError = nil
        status = "正在同步"
        let started = Date()
        defer { isSyncing = false; transferProgress = nil }
        do {
            try await prepareLocalBooks(model)
            // 本地编辑先写入队列, 拉取期间始终保护未上传的数据.
            SyncProjection.capture(books: model.books, events: model.readingStats.events, journal: &journal, now: now)
            try persist()
            try await pullAll(api)
            try applyRemote()
            var batches = 0
            while isSignedIn, !journal.pending.isEmpty {
                let batch = journal.batch()
                journal.attemptedIDs.formUnion(batch.map(\.changeID))
                try persist()
                let response = try await api.push(batch)
                updateClock(response.serverTime)
                // push 返回的游标不能替代 pull 游标, 否则会跳过其他设备的变更.
                try await pullAll(api)
                journal.acknowledge(response.acceptedIDs)
                journal.rebaseUnsent(after: batch.filter { response.acceptedIDs.contains($0.changeID) })
                try persist()
                try applyRemote()
                batches += 1
                if batches >= 100 { break }
            }
            try await uploadFiles(api, model: model)
            try await downloadCovers(api, model: model)
            journal.lastSyncedAt = Date()
            try persist()
            guard isSignedIn else { return }
            retryDelay = 2
            status = "已同步"
            logger.info("同步完成: pending=\(self.journal.pending.count), seconds=\(Date().timeIntervalSince(started))")
            schedule(delay: journal.pending.isEmpty ? 60 : 1)
        } catch {
            guard isSignedIn else { return }
            report(error)
            if case CloudSyncError.unauthorized = error { isSignedIn = false }
            else { schedule(delay: retryDelay); retryDelay = min(retryDelay * 2, 60) }
        }
    }

    func download(_ book: BookSummary) async -> Bool {
        guard let api, isSignedIn, let model, let canonicalID = book.canonicalID else {
            report(CloudSyncError.message("请登录后下载图书")); return false
        }
        guard downloading.insert(book.id).inserted else { return false }
        defer { downloading.remove(book.id); transferProgress = nil }
        do {
            status = "正在下载 " + book.title
            let temporary = try await api.download(bookID: canonicalID, kind: "content", progress: progressHandler())
            defer { try? FileManager.default.removeItem(at: temporary) }
            let store = model.libraryStore
            let staging = store.rootURL.appendingPathComponent("download-" + UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            try await Task.detached(priority: .utility) {
                _ = try BookArchive.unpack(archiveURL: temporary, destination: staging, expectedID: canonicalID)
                _ = try EPUBParser().parse(folderURL: staging)
            }.value
            guard model.books.contains(where: { $0.id == book.id }) else { return false }
            if FileManager.default.fileExists(atPath: book.folderURL.path) { try FileManager.default.removeItem(at: book.folderURL) }
            try FileManager.default.moveItem(at: staging, to: book.folderURL)
            try store.preserveArchive(temporary, for: book)
            NotificationCenter.default.post(name: .bookAssetsChanged, object: canonicalID)
            model.objectWillChange.send()
            status = "已下载"
            return true
        } catch { report(error); return false }
    }

    func downloadAll() async {
        guard let model else { return }
        for book in model.books where !model.libraryStore.isDownloaded(book) {
            if !(await download(book)) { break }
        }
    }

    private func configureAPI(_ server: URL) {
        let api = SyncAPI(server: server, credentials: credentials)
        api.onServerTime = { [weak self] time in self?.updateClock(time) }
        self.api = api
    }

    private func updateClock(_ serverTime: TimeInterval) {
        let adjusted = journal.calibrateClock(serverTime: serverTime, localTime: Date().timeIntervalSince1970)
        clockAnchor = (serverTime, ProcessInfo.processInfo.systemUptime)
        if adjusted {
            do { try persist(); try applyRemote() } catch { storageFailed = true; report(error) }
        }
    }

    private func persist() throws {
        try journalStore.save(journal)
        pendingCount = journal.pending.count
        lastSyncedAt = journal.lastSyncedAt
    }

    private func pullAll(_ api: SyncAPI) async throws {
        while true {
            let page = try await api.pull(cursor: journal.cursor)
            guard page.cursor >= journal.cursor, !page.hasMore || page.cursor > journal.cursor else { throw CloudSyncError.message("服务端同步游标未前进") }
            journal.receive(page)
            updateClock(page.serverTime)
            try persist()
            if !page.hasMore { break }
        }
    }

    private func applyRemote() throws {
        guard let model else { return }
        let projection = SyncProjection.apply(journal: journal, books: model.books, events: model.readingStats.events)
        try model.applySyncedLibrary(books: projection.books, events: projection.events, removed: projection.removed)
        for book in projection.removed {
            if let id = book.canonicalID {
                journal.uploadedContent.remove(id)
                journal.uploadedCovers.remove(id)
            }
        }
        SyncProjection.recordVisibleState(books: projection.books, journal: &journal)
        try persist()
    }

    private func prepareLocalBooks(_ model: AppModel) async throws {
        for book in model.books where book.canonicalID == nil {
            status = "正在准备 " + book.title
            let id = try await Task.detached(priority: .utility) { try BookArchive.fingerprint(folderURL: book.folderURL) }.value
            try model.assignCanonicalID(id, to: book.id)
        }
        try model.mergeDuplicateBooks()
    }

    private func uploadFiles(_ api: SyncAPI, model: AppModel) async throws {
        for book in model.books {
            guard let id = book.canonicalID, model.libraryStore.isDownloaded(book),
                  journal.records["book:" + id]?.deletedAt == nil,
                  journal.records["book:" + id] != nil else { continue }
            if !journal.uploadedContent.contains(id) {
                status = "正在上传 " + book.title
                if !(try await api.fileExists(bookID: id, kind: "content")) {
                    let store = model.libraryStore
                    let archive = try await Task.detached(priority: .utility) { try store.prepareArchive(for: book) }.value
                    try await api.upload(archive, bookID: id, kind: "content", progress: progressHandler())
                }
                journal.uploadedContent.insert(id)
                try persist()
            }
            if !journal.uploadedCovers.contains(id) {
                if let image = model.libraryStore.coverImage(for: book), let tiff = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]), png.count <= 10 * 1024 * 1024 {
                    let cover = model.libraryStore.cachedCoverURL(for: id)
                    try FileManager.default.createDirectory(at: cover.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: cover, options: .atomic)
                    try await api.upload(cover, bookID: id, kind: "cover", progress: progressHandler())
                }
                journal.uploadedCovers.insert(id)
                try persist()
            }
        }
    }

    private func downloadCovers(_ api: SyncAPI, model: AppModel) async throws {
        for book in model.books {
            guard let id = book.canonicalID, book.coverPath != nil else { continue }
            let target = model.libraryStore.cachedCoverURL(for: id)
            guard !FileManager.default.fileExists(atPath: target.path), try await api.fileExists(bookID: id, kind: "cover") else { continue }
            let file = try await api.download(bookID: id, kind: "cover", progress: { _ in })
            defer { try? FileManager.default.removeItem(at: file) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: file, to: target)
            NotificationCenter.default.post(name: .bookAssetsChanged, object: id)
            model.objectWillChange.send()
        }
    }

    private func progressHandler() -> @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { @MainActor in self?.transferProgress = min(max(fraction, 0), 1) }
        }
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        status = (error as? URLError) != nil ? "离线, 等待重试" : "同步失败"
        logger.error("同步失败: \(error.localizedDescription, privacy: .public)")
    }
}
