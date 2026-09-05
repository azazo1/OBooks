import Foundation
import OSLog

final class ReadingStatsStore {
    private struct Snapshot: Codable {
        let schemaVersion: Int
        let buckets: [ReadingTimeBucket]
    }

    private let snapshotURL: URL
    private let logger = Logger(subsystem: "com.obooks.app", category: "reading.stats")

    init(rootURL: URL) {
        snapshotURL = rootURL.appendingPathComponent("reading-stats.json")
    }

    func load() -> [ReadingTimeBucket] {
        guard let data = try? Data(contentsOf: snapshotURL) else {
            logger.info("没有找到阅读统计")
            return []
        }

        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard snapshot.schemaVersion == 1 else {
                logger.error("不支持的阅读统计版本: \(snapshot.schemaVersion)")
                return []
            }
            return snapshot.buckets
        } catch {
            logger.error("读取阅读统计失败: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ buckets: [ReadingTimeBucket]) {
        do {
            let snapshot = Snapshot(schemaVersion: 1, buckets: buckets)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            logger.error("保存阅读统计失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}
