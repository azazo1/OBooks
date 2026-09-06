import Foundation

protocol SyncCredentialStorage {
    func read() throws -> String?
    func write(_ value: String) throws
    func remove() throws
}

struct SyncCredentialStore: SyncCredentialStorage {
    private let url: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        url = rootURL.appendingPathComponent("sync-refresh-token")
    }

    func read() throws -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let value = try String(contentsOf: url, encoding: .utf8)
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    func write(_ value: String) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: url)
        if !fileManager.createFile(atPath: url.path, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600]) {
            throw CloudSyncError.message("写入同步凭据失败")
        }
    }

    func remove() throws {
        do {
            try fileManager.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        }
    }
}
