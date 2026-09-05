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
    var readingPosition: ReadingPosition?
    var bookmarks: [ReaderBookmark]
    var annotations: [ReaderAnnotation]
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
        isFinished: Bool = false,
        readingPosition: ReadingPosition? = nil,
        bookmarks: [ReaderBookmark] = [],
        annotations: [ReaderAnnotation] = []
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
        self.readingPosition = readingPosition
        self.bookmarks = bookmarks
        self.annotations = annotations
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

    mutating func toggleBookmark(at position: ReadingPosition, title: String, progressFraction: Double) {
        if let index = bookmarks.firstIndex(where: { $0.matches(position) }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(
                ReaderBookmark(position: position, title: title, progressFraction: progressFraction),
                at: 0
            )
        }
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
        case readingPosition
        case bookmarks
        case annotations
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
        readingPosition = try? container.decodeIfPresent(ReadingPosition.self, forKey: .readingPosition)
        bookmarks = try container.decodeIfPresent([ReaderBookmark].self, forKey: .bookmarks) ?? []
        annotations = try container.decodeIfPresent([ReaderAnnotation].self, forKey: .annotations) ?? []
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
        try container.encodeIfPresent(readingPosition, forKey: .readingPosition)
        try container.encode(bookmarks, forKey: .bookmarks)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(isFinished, forKey: .isFinished)
        try container.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encode(importedAt, forKey: .importedAt)
    }
}
