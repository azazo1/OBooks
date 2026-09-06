import AppKit
import Foundation
import OSLog

extension Notification.Name {
    static let bookAssetsChanged = Notification.Name("com.obooks.book-assets-changed")
}

enum LibraryStoreError: LocalizedError {
    case invalidBookFolder

    var errorDescription: String? {
        switch self {
        case .invalidBookFolder: return "图书文件夹无效"
        }
    }
}

final class LibraryStore {
    static let booksDirectoryURL: URL = {
        let fileManager = FileManager.default
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("OBooks/Books", isDirectory: true)
    }()

    let rootURL: URL
    private let snapshotURL: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.obooks.app", category: "persistence")
    private(set) var loadError: String?

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? Self.booksDirectoryURL.deletingLastPathComponent()
        snapshotURL = self.rootURL.appendingPathComponent("library.json")
        createDirectories()
    }

    func load() -> [BookSummary] {
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            logger.info("没有找到已有书库")
            return []
        }

        do {
            let data = try Data(contentsOf: snapshotURL)
            let snapshot = try LibraryMigration.decode(data)
            for book in snapshot.books {
                guard book.folderName == book.id.uuidString else { throw LibraryStoreError.invalidBookFolder }
                if let id = book.canonicalID {
                    guard id.count == 64, id.allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains(String($0))) }) else { throw LibraryStoreError.invalidBookFolder }
                }
            }
            return snapshot.books.map { original in
                var book = original
                book.storageRoot = rootURL
                return book
            }.filter { $0.canonicalID != nil || fileManager.fileExists(atPath: $0.folderURL.path) }
        } catch {
            loadError = error.localizedDescription
            logger.error("读取书库失败: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    @discardableResult
    func save(_ books: [BookSummary]) -> Bool {
        do {
            guard loadError == nil else { return false }
            let snapshot = LibrarySnapshot(schemaVersion: 2, books: books)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
            return true
        } catch {
            logger.error("保存书库失败: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func bookFolderURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("Books", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func deleteBookData(for book: BookSummary) throws {
        let folderURL = book.folderURL.standardizedFileURL
        let booksURL = rootURL.appendingPathComponent("Books", isDirectory: true).standardizedFileURL
        guard folderURL.deletingLastPathComponent() == booksURL else {
            throw LibraryStoreError.invalidBookFolder
        }
        if fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.removeItem(at: folderURL)
        }
        let archive = archiveURL(for: book)
        if fileManager.fileExists(atPath: archive.path) { try fileManager.removeItem(at: archive) }
    }

    func coverImage(for book: BookSummary) -> NSImage? {
        if let id = book.canonicalID, let image = NSImage(contentsOf: cachedCoverURL(for: id)) { return image }
        guard let coverPath = book.coverPath else {
            return nil
        }
        guard (try? BookArchive.validatePath(coverPath)) != nil else { return nil }
        return NSImage(contentsOf: book.folderURL.appendingPathComponent(coverPath))
    }

    func isDownloaded(_ book: BookSummary) -> Bool {
        fileManager.fileExists(atPath: book.folderURL.appendingPathComponent("META-INF/container.xml").path)
    }

    func archiveURL(for book: BookSummary) -> URL {
        rootURL.appendingPathComponent("Archives", isDirectory: true).appendingPathComponent(book.id.uuidString + ".epub")
    }

    func cachedCoverURL(for canonicalID: String) -> URL {
        rootURL.appendingPathComponent("Covers", isDirectory: true).appendingPathComponent(canonicalID + ".png")
    }

    func preserveArchive(_ source: URL, for book: BookSummary) throws {
        let target = archiveURL(for: book)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: target.path) { try fileManager.copyItem(at: source, to: target) }
    }

    func prepareArchive(for book: BookSummary) throws -> URL {
        let target = archiveURL(for: book)
        if fileManager.fileExists(atPath: target.path) { return target }
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? fileManager.removeItem(at: temporary) }
        try BookArchive.pack(folderURL: book.folderURL, archiveURL: temporary)
        try fileManager.moveItem(at: temporary, to: target)
        return target
    }

    private func createDirectories() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: rootURL.appendingPathComponent("Books", isDirectory: true), withIntermediateDirectories: true)
        } catch {
            logger.error("创建书库目录失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}
