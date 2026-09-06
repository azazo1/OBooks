import Foundation
import OSLog

struct ResumableDownload {
    struct Sidecar: Codable, Equatable {
        var etag: String
        var expectedSize: Int64?
    }

    let partialURL: URL
    let sidecarURL: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.obooks.app", category: "sync.download")

    static func content(rootURL: URL, bookID: String) -> ResumableDownload {
        let directory = rootURL.appendingPathComponent("Downloads", isDirectory: true)
        return ResumableDownload(
            partialURL: directory.appendingPathComponent(bookID + ".partial"),
            sidecarURL: directory.appendingPathComponent(bookID + ".partial.json")
        )
    }

    var localSize: Int64 {
        guard fileManager.fileExists(atPath: partialURL.path),
              let size = try? fileManager.attributesOfItem(atPath: partialURL.path)[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    func loadSidecar() -> Sidecar? {
        guard let data = try? Data(contentsOf: sidecarURL) else { return nil }
        return try? JSONDecoder().decode(Sidecar.self, from: data)
    }

    // 返回 Range 起点. 已完整时返回本地大小, 调用方跳过 GET.
    func prepare(remoteETag: String?, remoteSize: Int64?) throws -> Int64 {
        try fileManager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = localSize
        let sidecar = loadSidecar()
        if size <= 0 || sidecar == nil {
            if size > 0 { logger.info("部分文件缺少 sidecar, 重新下载") }
            try remove()
            return 0
        }
        if let remoteETag, sidecar?.etag != remoteETag {
            logger.info("部分文件 ETag 已变化, 重新下载")
            try remove()
            return 0
        }
        if let remoteSize, size > remoteSize {
            logger.info("部分文件大于远端, 重新下载")
            try remove()
            return 0
        }
        return size
    }

    func openHandle(reset: Bool) throws -> FileHandle {
        try fileManager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if reset || !fileManager.fileExists(atPath: partialURL.path) {
            try Data().write(to: partialURL, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: partialURL)
        if reset {
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
        } else {
            try handle.seekToEnd()
        }
        return handle
    }

    func saveSidecar(_ sidecar: Sidecar) throws {
        try JSONEncoder().encode(sidecar).write(to: sidecarURL, options: .atomic)
    }

    func remove() throws {
        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }
        if fileManager.fileExists(atPath: sidecarURL.path) {
            try fileManager.removeItem(at: sidecarURL)
        }
    }
}
