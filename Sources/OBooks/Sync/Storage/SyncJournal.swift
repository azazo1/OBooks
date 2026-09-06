import Foundation

struct SyncAccount: Codable, Equatable {
    var server: URL
    var username: String
    var userID: String
}

struct SyncJournal: Codable {
    var schemaVersion = 1
    var deviceID = UUID().uuidString
    var deviceName = Host.current().localizedName ?? "Mac"
    var account: SyncAccount?
    var cursor: Int64 = 0
    var clockOffset: TimeInterval = 0
    var attemptedIDs: Set<String> = []
    var records: [String: SyncChange] = [:]
    var localPayloads: [String: SyncPayload] = [:]
    var localRevisions: [String: Int64] = [:]
    var pending: [SyncChange] = []
    var uploadedContent: Set<String> = []
    var uploadedCovers: Set<String> = []
    var lastSyncedAt: Date?

    func effective(_ key: String) -> SyncChange? {
        pending.last(where: { $0.key == key }) ?? records[key]
    }

    mutating func capture(entity: String, entityID: String, bookID: String, payload: SyncPayload, modifiedAt: Date) {
        let key = entity + ":" + entityID.lowercased()
        guard localPayloads[key] != payload else { return }
        let base = entity == "book" && records[key]?.deletedAt != nil ? records[key]?.revision : localRevisions[key]
        enqueue(entity: entity, entityID: entityID, bookID: bookID, payload: payload, modifiedAt: modifiedAt, baseRevision: base ?? 0)
        localPayloads[key] = payload
    }

    mutating func enqueue(entity: String, entityID: String, bookID: String, payload: SyncPayload, modifiedAt: Date, deleted: Bool = false, baseRevision: Int64? = nil) {
        let key = entity + ":" + entityID.lowercased()
        let previous = effective(key)
        if let previous, (previous.deletedAt != nil) == deleted, (deleted || previous.payload == payload) { return }
        // 已持久化的操作内容不再改写, 网络重试始终使用相同的 ID 和内容.
        pending.append(SyncChange(
            deviceID: deviceID, entity: entity, entityID: entityID, bookID: bookID,
            baseRevision: baseRevision ?? records[key]?.revision ?? 0,
            modifiedAt: modifiedAt.timeIntervalSince1970,
            deletedAt: deleted ? modifiedAt.timeIntervalSince1970 : nil,
            payload: payload
        ))
    }

    func batch() -> [SyncChange] {
        var seen = Set<String>()
        return Array(pending.filter { seen.insert($0.key).inserted }.prefix(100))
    }

    mutating func acknowledge(_ ids: [String]) {
        let accepted = Set(ids)
        pending.removeAll { accepted.contains($0.changeID) }
        attemptedIDs.subtract(accepted)
    }

    mutating func calibrateClock(serverTime: TimeInterval, localTime: TimeInterval) -> Bool {
        let offset = serverTime - localTime
        let adjustment = offset - clockOffset
        clockOffset = offset
        guard abs(adjustment) > 5 else { return false }
        for index in pending.indices where !attemptedIDs.contains(pending[index].changeID) {
            pending[index].modifiedAt = max(0, pending[index].modifiedAt + adjustment)
            if let deleted = pending[index].deletedAt { pending[index].deletedAt = max(0, deleted + adjustment) }
            if let date = pending[index].payload.progress?.lastOpenedAt { pending[index].payload.progress?.lastOpenedAt = date.addingTimeInterval(adjustment) }
            if let date = pending[index].payload.annotation?.modifiedAt { pending[index].payload.annotation?.modifiedAt = date.addingTimeInterval(adjustment) }
            if let date = pending[index].payload.bookmark?.modifiedAt { pending[index].payload.bookmark?.modifiedAt = date.addingTimeInterval(adjustment) }
        }
        return true
    }

    mutating func receive(_ page: SyncPull) {
        for change in page.changes {
            guard change.revision > (records[change.key]?.revision ?? 0) else { continue }
            records[change.key] = change
        }
        cursor = page.cursor
    }

    // 同一设备排队的后续编辑基于前一次已确认的版本, 不视为跨设备冲突.
    mutating func rebaseUnsent(after accepted: [SyncChange]) {
        for previous in accepted {
            guard let current = records[previous.key], current.changeID == previous.changeID else { continue }
            for index in pending.indices where pending[index].key == previous.key && !attemptedIDs.contains(pending[index].changeID) {
                pending[index].baseRevision = current.revision
            }
        }
    }
}

final class SyncJournalStore {
    let url: URL

    init(rootURL: URL) { url = rootURL.appendingPathComponent("sync-state.json") }

    func load() throws -> SyncJournal {
        guard FileManager.default.fileExists(atPath: url.path) else { return SyncJournal() }
        let journal = try SyncCoding.decoder().decode(SyncJournal.self, from: Data(contentsOf: url))
        guard journal.schemaVersion == 1 else { throw CloudSyncError.message("不支持的同步数据版本") }
        return journal
    }

    func save(_ journal: SyncJournal) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyncCoding.encoder().encode(journal).write(to: url, options: .atomic)
    }
}
