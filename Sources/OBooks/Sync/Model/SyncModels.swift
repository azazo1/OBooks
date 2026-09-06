import Foundation

struct CloudBook: Codable, Equatable {
    var title: String
    var authors: [String]
    var sortTitle: String
    var sourceFileName: String
    var coverPath: String?
    var spine: [EPUBSpineItem]
    var toc: [EPUBTOCItem]
    var importedAt: Date
    var isFinished: Bool
    var isHiddenFromContinueReading: Bool

    init(_ book: BookSummary) {
        title = book.title
        authors = book.authors
        sortTitle = book.sortTitle
        sourceFileName = book.sourceFileName
        coverPath = book.coverPath
        spine = book.spine
        toc = book.toc
        importedAt = book.importedAt
        isFinished = book.isFinished
        isHiddenFromContinueReading = book.isHiddenFromContinueReading
    }

    func localBook(id: UUID = UUID(), canonicalID: String) -> BookSummary {
        var book = BookSummary(
            id: id, title: title, authors: authors, sortTitle: sortTitle,
            sourceFileName: sourceFileName, folderName: id.uuidString, coverPath: coverPath,
            spine: spine, toc: toc, progressFraction: 0, lastOpenedAt: nil, importedAt: importedAt,
            isFinished: isFinished, isHiddenFromContinueReading: isHiddenFromContinueReading
        )
        book.canonicalID = canonicalID
        return book
    }
}

struct CloudProgress: Codable, Equatable {
    var fraction: Double
    var position: ReadingPosition?
    var lastOpenedAt: Date?
}

struct ReadingEvent: Codable, Equatable, Identifiable {
    let id: UUID
    var bookID: UUID
    let day: ReadingDay
    let hour: Int
    let seconds: TimeInterval
}

struct CloudReadingEvent: Codable, Equatable {
    var id: UUID
    var day: ReadingDay
    var hour: Int
    var seconds: TimeInterval
}

struct SyncPayload: Codable, Equatable {
    var book: CloudBook?
    var progress: CloudProgress?
    var bookmark: ReaderBookmark?
    var annotation: ReaderAnnotation?
    var readingEvent: CloudReadingEvent?
}

struct SyncChange: Codable, Equatable {
    var deviceID: String
    var changeID: String = UUID().uuidString
    var entity: String
    var entityID: String
    var bookID: String
    var baseRevision: Int64 = 0
    var revision: Int64 = 0
    var modifiedAt: TimeInterval
    var deletedAt: TimeInterval?
    var conflictOf: String?
    var payload: SyncPayload

    var key: String { entity + ":" + entityID.lowercased() }
}

struct SyncPull: Codable {
    var changes: [SyncChange]
    var cursor: Int64
    var hasMore: Bool
    var serverTime: TimeInterval
}

struct SyncPush: Codable {
    var acceptedIDs: [String]
    var conflicts: Int
    var cursor: Int64
    var serverTime: TimeInterval
}

struct SyncTokens: Codable {
    var userID: String
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var serverTime: TimeInterval
}

enum SyncCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

enum CloudSyncError: LocalizedError {
    case message(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .unauthorized: return "会话已过期, 请重新登录"
        }
    }

    static func forLogin(_ error: Error) -> CloudSyncError {
        if let urlError = error as? URLError { return .message(connectionMessage(urlError)) }
        if let cloud = error as? CloudSyncError {
            if case .unauthorized = cloud { return .message("账号或密码无效") }
            return cloud
        }
        return .message(error.localizedDescription)
    }

    static func connectionMessage(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return "网络不可用"
        case .timedOut:
            return "连接服务器超时"
        case .cannotFindHost, .dnsLookupFailed:
            return "找不到服务器"
        default:
            return "无法连接服务器"
        }
    }
}
