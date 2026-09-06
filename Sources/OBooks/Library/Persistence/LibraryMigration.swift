import Foundation

struct LibrarySnapshot: Codable {
    var schemaVersion: Int
    var books: [BookSummary]
}

enum LibraryMigration {
    static func decode(_ data: Data) throws -> LibrarySnapshot {
        var snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        switch snapshot.schemaVersion {
        case 1:
            snapshot.schemaVersion = 2
        case 2:
            break
        default:
            throw CloudSyncError.message("不支持的书库版本: \(snapshot.schemaVersion)")
        }
        return snapshot
    }
}
