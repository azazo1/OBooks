import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var books: [BookSummary]
    @Published var selectedBookID: UUID?
    @Published var openBook: BookSummary?
    @Published var alert: AppAlert?

    let libraryStore: LibraryStore
    private let logger = Logger(subsystem: "com.obooks.app", category: "app")
    private var readerWindows: [UUID: NSWindow] = [:]
    private var readerDelegates: [UUID: ReaderWindowDelegate] = [:]

    init() {
        let store = LibraryStore()
        libraryStore = store
        books = store.load()
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
        do {
            let book = try EPUBImporter(store: libraryStore).importBook(from: url)
            books.removeAll { $0.id == book.id }
            books.append(book)
            books.sort { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
            libraryStore.save(books)
            selectedBookID = book.id
            openReader(book)
            logger.info("导入完成: title=\(book.title, privacy: .public)")
        } catch {
            logger.error("导入失败: file=\(url.lastPathComponent, privacy: .public), error=\(error.localizedDescription, privacy: .public)")
            alert = AppAlert(message: error.localizedDescription)
        }
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
        updateLastOpened(book.id)
        openReader(book)
    }

    func openReader(_ book: BookSummary) {
        if let window = readerWindows[book.id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let reader = ReaderView(book: book).environmentObject(self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = book.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = NSHostingController(rootView: reader)
        window.center()
        let delegate = ReaderWindowDelegate { [weak self] in
            self?.readerWindows.removeValue(forKey: book.id)
            self?.readerDelegates.removeValue(forKey: book.id)
        }
        window.delegate = delegate
        readerDelegates[book.id] = delegate
        readerWindows[book.id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateProgress(bookID: UUID, fraction: Double) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else {
            return
        }
        let normalized = min(max(fraction, 0), 1)
        guard abs(books[index].progressFraction - normalized) > 0.005 else {
            return
        }
        books[index].progressFraction = normalized
        books[index].lastOpenedAt = Date()
        libraryStore.save(books)
    }

    private func updateLastOpened(_ bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else {
            return
        }
        books[index].lastOpenedAt = Date()
        libraryStore.save(books)
    }
}
