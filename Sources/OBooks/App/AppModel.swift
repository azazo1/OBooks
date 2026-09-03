import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

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
            openBook = book
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
        openBook = book
    }

    func open(_ book: BookSummary) {
        selectedBookID = book.id
        openBook = book
        updateLastOpened(book.id)
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
