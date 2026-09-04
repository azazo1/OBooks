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
            try validateArchive(at: sourceURL)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try runUnzip(sourceURL: sourceURL, destination: destination)
            let package = try EPUBParser().parse(folderURL: destination)
            let title = package.title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : package.title
            let book = BookSummary(id: id, title: title, authors: package.authors, sortTitle: title.localizedLowercase,
                sourceFileName: sourceURL.lastPathComponent, folderName: id.uuidString, coverPath: package.coverPath,
                spine: package.spine, toc: package.toc, progressFraction: 0, lastOpenedAt: nil, importedAt: Date(), isFinished: false)
            logger.info("导入完成: chapters=\(package.spine.count), seconds=\(Date().timeIntervalSince(startedAt), privacy: .public)")
            return book
        } catch { try? fileManager.removeItem(at: destination); throw error }
    }

    private func validateArchive(at url: URL) throws {
        let output = try runProcess("/usr/bin/unzip", arguments: ["-Z1", url.path])
        for line in output.split(whereSeparator: \.isNewline) {
            let path = String(line); let decoded = path.removingPercentEncoding ?? path
            if decoded.hasPrefix("/") || decoded.split(separator: "/").contains("..") { throw EPUBImportError.unsafeArchivePath(path) }
        }
    }

    private func runUnzip(sourceURL: URL, destination: URL) throws { _ = try runProcess("/usr/bin/unzip", arguments: ["-q", "-o", sourceURL.path, "-d", destination.path]) }

    @discardableResult
    private func runProcess(_ executable: String, arguments: [String]) throws -> String {
        let process = Process(); let outputPipe = Pipe(); let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = outputPipe; process.standardError = errorPipe
        try process.run(); process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw EPUBImportError.archiveCommandFailed(error.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return output
    }
}
