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
    var lastOpenedAt: Date?
    let importedAt: Date

    var authorLabel: String {
        authors.isEmpty ? "未知作者" : authors.joined(separator: ", ")
    }

    var folderURL: URL {
        LibraryStore.booksDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
    }
}
