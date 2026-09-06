import Foundation
import CryptoKit

struct ReadingStatsSnapshot: Codable {
    var schemaVersion: Int
    var events: [ReadingEvent]
}

enum ReadingStatsMigration {
    private struct Version: Decodable { var schemaVersion: Int }
    private struct Legacy: Decodable { var buckets: [ReadingTimeBucket] }

    static func decode(_ data: Data) throws -> ReadingStatsSnapshot {
        let decoder = JSONDecoder()
        switch try decoder.decode(Version.self, from: data).schemaVersion {
        case 1:
            let legacy = try decoder.decode(Legacy.self, from: data)
            return ReadingStatsSnapshot(schemaVersion: 2, events: legacy.buckets.map {
                ReadingEvent(id: legacyID($0), bookID: $0.bookID, day: $0.day, hour: $0.hour, seconds: $0.seconds)
            })
        case 2:
            return try decoder.decode(ReadingStatsSnapshot.self, from: data)
        default:
            throw CloudSyncError.message("不支持的阅读统计版本")
        }
    }

    private static func legacyID(_ bucket: ReadingTimeBucket) -> UUID {
        let identity = "obooks-stats-v1:\(bucket.bookID):\(bucket.day.year)-\(bucket.day.month)-\(bucket.day.day):\(bucket.hour):\(bucket.seconds)"
        let hex = SHA256.hash(data: Data(identity.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex)
        let string = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
        return UUID(uuidString: string)!
    }
}
