import AppKit
import Foundation
import OSLog

final class LibraryStore {
    private struct Snapshot: Codable {
        let schemaVersion: Int
        let books: [BookSummary]
    }

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

    init() {
        rootURL = Self.booksDirectoryURL.deletingLastPathComponent()
        snapshotURL = rootURL.appendingPathComponent("library.json")
        createDirectories()
    }

    func load() -> [BookSummary] {
        guard let data = try? Data(contentsOf: snapshotURL) else {
            logger.info("没有找到已有书库")
            return []
        }

        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard snapshot.schemaVersion == 1 else {
                logger.error("不支持的书库版本: \(snapshot.schemaVersion)")
                return []
            }
            return snapshot.books.filter { fileManager.fileExists(atPath: $0.folderURL.path) }
        } catch {
            logger.error("读取书库失败: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ books: [BookSummary]) {
        do {
            let snapshot = Snapshot(schemaVersion: 1, books: books)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            logger.error("保存书库失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    func bookFolderURL(for id: UUID) -> URL {
        Self.booksDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func coverImage(for book: BookSummary) -> NSImage? {
        guard let coverPath = book.coverPath else {
            return nil
        }
        return NSImage(contentsOf: book.folderURL.appendingPathComponent(coverPath))
    }

    private func createDirectories() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: Self.booksDirectoryURL, withIntermediateDirectories: true)
        } catch {
            logger.error("创建书库目录失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}
