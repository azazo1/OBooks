import CryptoKit
import Foundation
import OSLog
import ZIPFoundation

enum BookArchive {
    private static let logger = Logger(subsystem: "com.obooks.app", category: "sync.archive")

    static func validatePath(_ path: String) throws {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.contains("\\"), !trimmed.contains("\0"),
              trimmed.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw EPUBImportError.unsafeArchivePath(path)
        }
    }

    static func fingerprint(archiveURL: URL) throws -> String {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let entries = Array(archive).sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        guard entries.count <= 50_000 else { throw CloudSyncError.message("EPUB 条目过多") }
        var manifest = SHA256()
        var seen = Set<String>()
        var total: UInt64 = 0
        var hasMimetype = false
        var hasContainer = false
        for entry in entries {
            try validatePath(entry.path)
            guard entry.type != .symlink else { throw EPUBImportError.unsafeArchivePath(entry.path) }
            guard entry.type == .file else { continue }
            guard seen.insert(entry.path).inserted, entry.uncompressedSize <= 256 * 1024 * 1024 else { throw EPUBImportError.invalidFile }
            total += entry.uncompressedSize
            guard total <= 1024 * 1024 * 1024 else { throw CloudSyncError.message("EPUB 解压体积过大") }
            var hash = SHA256()
            var bytes: UInt64 = 0
            _ = try archive.extract(entry) { data in
                bytes += UInt64(data.count)
                guard bytes <= entry.uncompressedSize else { throw EPUBImportError.invalidFile }
                hash.update(data: data)
            }
            guard bytes == entry.uncompressedSize else { throw EPUBImportError.invalidFile }
            let digest = Data(hash.finalize())
            if entry.path == "mimetype" { hasMimetype = digest == Data(SHA256.hash(data: Data("application/epub+zip".utf8))) }
            if entry.path == "META-INF/container.xml" { hasContainer = true }
            manifest.update(data: Data("\(entry.path)\0\(bytes)\0".utf8))
            manifest.update(data: digest)
        }
        guard hasMimetype, hasContainer else { throw EPUBImportError.invalidFile }
        return manifest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprint(folderURL: URL) throws -> String {
        let files = try paths(in: folderURL)
        var manifest = SHA256()
        var total: UInt64 = 0
        for path in files {
            let url = folderURL.appendingPathComponent(path)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            var count: UInt64 = 0
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hash.update(data: chunk)
                count += UInt64(chunk.count)
                guard count <= 256 * 1024 * 1024 else { throw EPUBImportError.invalidFile }
            }
            total += count
            guard total <= 1024 * 1024 * 1024 else { throw EPUBImportError.invalidFile }
            manifest.update(data: Data("\(path)\0\(count)\0".utf8))
            manifest.update(data: Data(hash.finalize()))
        }
        return manifest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func pack(folderURL: URL, archiveURL: URL) throws {
        logger.info("开始打包本地图书")
        let files = try paths(in: folderURL)
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for path in ["mimetype"] + files.filter({ $0 != "mimetype" }) {
            try archive.addEntry(with: path, relativeTo: folderURL, compressionMethod: path == "mimetype" ? .none : .deflate)
        }
        logger.info("本地图书打包完成: files=\(files.count)")
    }

    static func unpack(archiveURL: URL, destination: URL, expectedID: String? = nil) throws -> String {
        let fingerprint = try fingerprint(archiveURL: archiveURL)
        if let expectedID, fingerprint != expectedID { throw CloudSyncError.message("下载的 EPUB 内容指纹不匹配") }
        try FileManager.default.unzipItem(at: archiveURL, to: destination)
        return fingerprint
    }

    private static func paths(in folder: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, errorHandler: { _, error in
            traversalError = error
            return false
        }) else { throw EPUBImportError.invalidFile }
        var paths: [String] = []
        let prefix = folder.standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw EPUBImportError.unsafeArchivePath(url.lastPathComponent) }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, url.standardizedFileURL.path.hasPrefix(prefix) else { throw EPUBImportError.invalidFile }
            let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            try validatePath(path)
            paths.append(path)
            guard paths.count <= 50_000 else { throw EPUBImportError.invalidFile }
        }
        if let traversalError { throw traversalError }
        guard paths.contains("mimetype"), paths.contains("META-INF/container.xml") else { throw EPUBImportError.invalidFile }
        return paths.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
}
