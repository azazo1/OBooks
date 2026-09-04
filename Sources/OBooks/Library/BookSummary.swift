import Foundation

struct BookSummary: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var authors: [String]
    var sortTitle: String
    var sourceFileName: String
    var folderName: String
    var coverPath: String?
    var spine: [EPUBSpineItem]
    var toc: [EPUBTOCItem]
    var progressFraction: Double
    var isFinished: Bool
    var lastOpenedAt: Date?
    let importedAt: Date

    static let finishPromptThreshold = 0.95

    init(
        id: UUID,
        title: String,
        authors: [String],
        sortTitle: String,
        sourceFileName: String,
        folderName: String,
        coverPath: String?,
        spine: [EPUBSpineItem],
        toc: [EPUBTOCItem],
        progressFraction: Double,
        lastOpenedAt: Date?,
        importedAt: Date,
        isFinished: Bool = false
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.sortTitle = sortTitle
        self.sourceFileName = sourceFileName
        self.folderName = folderName
        self.coverPath = coverPath
        self.spine = spine
        self.toc = toc
        self.progressFraction = progressFraction
        self.isFinished = isFinished
        self.lastOpenedAt = lastOpenedAt
        self.importedAt = importedAt
    }

    var authorLabel: String {
        authors.isEmpty ? "未知作者" : authors.joined(separator: ", ")
    }

    var folderURL: URL {
        LibraryStore.booksDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    var isNearCompletion: Bool {
        !isFinished && progressFraction >= Self.finishPromptThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case authors
        case sortTitle
        case sourceFileName
        case folderName
        case coverPath
        case spine
        case toc
        case progressFraction
        case isFinished
        case lastOpenedAt
        case importedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        authors = try container.decode([String].self, forKey: .authors)
        sortTitle = try container.decode(String.self, forKey: .sortTitle)
        sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        folderName = try container.decode(String.self, forKey: .folderName)
        coverPath = try container.decodeIfPresent(String.self, forKey: .coverPath)
        spine = try container.decode([EPUBSpineItem].self, forKey: .spine)
        toc = try container.decode([EPUBTOCItem].self, forKey: .toc)
        progressFraction = try container.decode(Double.self, forKey: .progressFraction)
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(authors, forKey: .authors)
        try container.encode(sortTitle, forKey: .sortTitle)
        try container.encode(sourceFileName, forKey: .sourceFileName)
        try container.encode(folderName, forKey: .folderName)
        try container.encodeIfPresent(coverPath, forKey: .coverPath)
        try container.encode(spine, forKey: .spine)
        try container.encode(toc, forKey: .toc)
        try container.encode(progressFraction, forKey: .progressFraction)
        try container.encode(isFinished, forKey: .isFinished)
        try container.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encode(importedAt, forKey: .importedAt)
    }
}
