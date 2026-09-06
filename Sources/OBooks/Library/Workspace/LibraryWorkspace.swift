import CryptoKit
import Foundation
import OSLog

struct LibraryProfile: Codable, Identifiable, Equatable {
    static let unboundID = "unbound"

    var id: String
    var kind: String
    var server: URL?
    var username: String?
    var userID: String?

    var isUnbound: Bool { id == Self.unboundID }
    var title: String {
        if isUnbound { return "未绑定书库" }
        let user = username ?? "账号"
        let host = server?.host ?? server?.absoluteString ?? "服务器"
        return user + " @ " + host
    }
}

struct LibraryWorkspaceSnapshot: Codable {
    var schemaVersion: Int
    var activeID: String
    var profiles: [LibraryProfile]
}

final class LibraryWorkspace {
    let baseURL: URL
    private(set) var snapshot: LibraryWorkspaceSnapshot
    private let fileManager = FileManager.default

    var activeID: String { snapshot.activeID }
    var activeRoot: URL { root(for: snapshot.activeID) }
    var profiles: [LibraryProfile] { snapshot.profiles }
    var activeProfile: LibraryProfile? { snapshot.profiles.first { $0.id == snapshot.activeID } }

    static func profileID(server: URL, username: String) -> String {
        let material = Data((server.absoluteString + "\n" + username).utf8)
        return SHA256.hash(data: material).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func openDefault() throws -> LibraryWorkspace {
        let fileManager = FileManager.default
        let support = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return try LibraryWorkspace(baseURL: support.appendingPathComponent("OBooks", isDirectory: true))
    }

    init(baseURL: URL) throws {
        self.baseURL = baseURL
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let url = baseURL.appendingPathComponent("workspace.json")
        if fileManager.fileExists(atPath: url.path) {
            snapshot = try JSONDecoder().decode(LibraryWorkspaceSnapshot.self, from: Data(contentsOf: url))
            guard snapshot.schemaVersion == 1 else { throw CloudSyncError.message("不支持的书库工作区版本") }
        } else {
            snapshot = try Self.relocateIfNeeded(baseURL: baseURL)
            try Self.write(snapshot, to: url)
        }
        try fileManager.createDirectory(at: root(for: snapshot.activeID), withIntermediateDirectories: true)
    }

    func root(for profileID: String) -> URL {
        if profileID == LibraryProfile.unboundID {
            return baseURL.appendingPathComponent("unbound", isDirectory: true)
        }
        return baseURL.appendingPathComponent("profiles", isDirectory: true).appendingPathComponent(profileID, isDirectory: true)
    }

    func profile(server: URL, username: String) -> LibraryProfile? {
        let id = Self.profileID(server: server, username: username)
        return snapshot.profiles.first { $0.id == id }
    }

    func ensureAccountProfile(server: URL, username: String) throws -> LibraryProfile {
        let id = Self.profileID(server: server, username: username)
        if let existing = snapshot.profiles.first(where: { $0.id == id }) { return existing }
        let profile = LibraryProfile(id: id, kind: "account", server: server, username: username, userID: nil)
        snapshot.profiles.append(profile)
        try fileManager.createDirectory(at: root(for: id), withIntermediateDirectories: true)
        try persist()
        return profile
    }

    func setActive(_ profileID: String) throws {
        guard snapshot.profiles.contains(where: { $0.id == profileID }) else {
            throw CloudSyncError.message("找不到本地书库")
        }
        snapshot.activeID = profileID
        try fileManager.createDirectory(at: root(for: profileID), withIntermediateDirectories: true)
        try persist()
    }

    func updateUserID(_ userID: String, for profileID: String) throws {
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        snapshot.profiles[index].userID = userID
        try persist()
    }

    func sources(excluding active: String) -> [LibraryProfile] {
        snapshot.profiles.filter { $0.id != active }.filter { profile in
            let store = LibraryStore(rootURL: root(for: profile.id))
            return !store.load().isEmpty
        }
    }

    private func persist() throws {
        try Self.write(snapshot, to: baseURL.appendingPathComponent("workspace.json"))
    }

    private static func write(_ snapshot: LibraryWorkspaceSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private static func relocateIfNeeded(baseURL: URL) throws -> LibraryWorkspaceSnapshot {
        let fileManager = FileManager.default
        let unbound = LibraryProfile(id: LibraryProfile.unboundID, kind: "unbound", server: nil, username: nil, userID: nil)
        let legacyItems = ["library.json", "reading-stats.json", "sync-state.json", "sync-refresh-token", "Books", "Archives", "Covers"]
        let hasLegacy = legacyItems.contains { fileManager.fileExists(atPath: baseURL.appendingPathComponent($0).path) }
        guard hasLegacy else {
            try fileManager.createDirectory(at: baseURL.appendingPathComponent("unbound", isDirectory: true), withIntermediateDirectories: true)
            return LibraryWorkspaceSnapshot(schemaVersion: 1, activeID: LibraryProfile.unboundID, profiles: [unbound])
        }

        var profile = unbound
        if let data = try? Data(contentsOf: baseURL.appendingPathComponent("sync-state.json")),
           let journal = try? SyncCoding.decoder().decode(SyncJournal.self, from: data),
           let account = journal.account {
            profile = LibraryProfile(
                id: profileID(server: account.server, username: account.username),
                kind: "account",
                server: account.server,
                username: account.username,
                userID: account.userID
            )
        }

        let target = profile.isUnbound
            ? baseURL.appendingPathComponent("unbound", isDirectory: true)
            : baseURL.appendingPathComponent("profiles", isDirectory: true).appendingPathComponent(profile.id, isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for name in legacyItems {
            let source = baseURL.appendingPathComponent(name)
            let destination = target.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            if fileManager.fileExists(atPath: destination.path) { continue }
            try fileManager.moveItem(at: source, to: destination)
        }

        var profiles = [unbound]
        if !profile.isUnbound { profiles.append(profile) }
        Logger(subsystem: "com.obooks.app", category: "library.workspace").info("已把原书库目录迁入 \(profile.id, privacy: .public)")
        return LibraryWorkspaceSnapshot(schemaVersion: 1, activeID: profile.id, profiles: profiles)
    }
}
