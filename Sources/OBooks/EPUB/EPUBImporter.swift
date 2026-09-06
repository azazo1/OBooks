import Foundation
import OSLog

struct EPUBImporter {
    let store: LibraryStore
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.obooks.app", category: "epub.import")

    func importBook(from sourceURL: URL) throws -> BookSummary {
        guard sourceURL.pathExtension.lowercased() == "epub", fileManager.fileExists(atPath: sourceURL.path) else { throw EPUBImportError.invalidFile }
        let id = UUID()
        let destination = store.bookFolderURL(for: id)
        let startedAt = Date()
        logger.info("开始导入: file=\(sourceURL.lastPathComponent, privacy: .public)")
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let canonicalID = try BookArchive.unpack(archiveURL: sourceURL, destination: destination)
            let package = try EPUBParser().parse(folderURL: destination)
            let title = package.title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : package.title
            var book = BookSummary(id: id, title: title, authors: package.authors, sortTitle: title.localizedLowercase,
                sourceFileName: sourceURL.lastPathComponent, folderName: id.uuidString, coverPath: package.coverPath,
                spine: package.spine, toc: package.toc, progressFraction: 0, lastOpenedAt: nil, importedAt: Date(), isFinished: false)
            book.canonicalID = canonicalID
            book.storageRoot = store.rootURL
            try store.preserveArchive(sourceURL, for: book)
            logger.info("导入完成: chapters=\(package.spine.count), seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            return book
        } catch { try? fileManager.removeItem(at: destination); throw error }
    }

}
