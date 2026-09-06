import Foundation
import OSLog

final class ReadingStatsStore {
    private let snapshotURL: URL
    private let logger = Logger(subsystem: "com.obooks.app", category: "reading.stats")
    private(set) var loadError: String?

    init(rootURL: URL) {
        snapshotURL = rootURL.appendingPathComponent("reading-stats.json")
    }

    func load() -> [ReadingTimeBucket] {
        loadEvents().map { ReadingTimeBucket(bookID: $0.bookID, day: $0.day, hour: $0.hour, seconds: $0.seconds) }
    }

    func loadEvents() -> [ReadingEvent] {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            logger.info("没有找到阅读统计")
            return []
        }

        do {
            let data = try Data(contentsOf: snapshotURL)
            let snapshot = try ReadingStatsMigration.decode(data)
            if !saveEvents(snapshot.events) { throw CloudSyncError.message("阅读统计迁移保存失败") }
            return snapshot.events
        } catch {
            loadError = error.localizedDescription
            logger.error("读取阅读统计失败: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ buckets: [ReadingTimeBucket]) {
        let events = buckets.map { ReadingEvent(id: UUID(), bookID: $0.bookID, day: $0.day, hour: $0.hour, seconds: $0.seconds) }
        saveEvents(events)
    }

    @discardableResult
    func saveEvents(_ events: [ReadingEvent]) -> Bool {
        do {
            guard loadError == nil else { return false }
            let snapshot = ReadingStatsSnapshot(schemaVersion: 2, events: events)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
            return true
        } catch {
            logger.error("保存阅读统计失败: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
