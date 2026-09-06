import Foundation
import OSLog

enum LibraryCopy {
    private static let logger = Logger(subsystem: "com.obooks.app", category: "library.copy")

    struct Result {
        var added = 0
        var merged = 0
        var events = 0
    }

    static func merge(
        from sourceRoot: URL,
        into destStore: LibraryStore,
        destBooks: inout [BookSummary],
        destEvents: inout [ReadingEvent],
        progress: ((String) -> Void)? = nil
    ) async throws -> Result {
        let sourceStore = LibraryStore(rootURL: sourceRoot)
        let sourceBooks = sourceStore.load()
        let sourceEvents = ReadingStatsStore(rootURL: sourceRoot).loadEvents()
        var result = Result()
        let total = max(sourceBooks.count, 1)
        for (index, source) in sourceBooks.enumerated() {
            progress?("正在复制 \(index + 1)/\(total) \(source.title)")
            await Task.yield()
            if let canonicalID = source.canonicalID,
               let destIndex = destBooks.firstIndex(where: { $0.canonicalID == canonicalID }) {
                destBooks[destIndex] = try mergeBook(
                    dest: destBooks[destIndex],
                    source: source,
                    sourceStore: sourceStore,
                    destStore: destStore
                )
                let destID = destBooks[destIndex].id
                result.events += appendEvents(sourceEvents.filter { $0.bookID == source.id }, destBookID: destID, into: &destEvents)
                result.merged += 1
            } else {
                let copied = try copyBook(source, sourceStore: sourceStore, destStore: destStore)
                destBooks.append(copied)
                result.events += appendEvents(sourceEvents.filter { $0.bookID == source.id }, destBookID: copied.id, into: &destEvents)
                result.added += 1
            }
        }
        destBooks.sort { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        logger.info("复制完成: added=\(result.added), merged=\(result.merged), events=\(result.events)")
        return result
    }

    private static func copyBook(_ source: BookSummary, sourceStore: LibraryStore, destStore: LibraryStore) throws -> BookSummary {
        let id = UUID()
        var book = BookSummary(
            id: id,
            title: source.title,
            authors: source.authors,
            sortTitle: source.sortTitle,
            sourceFileName: source.sourceFileName,
            folderName: id.uuidString,
            coverPath: source.coverPath,
            spine: source.spine,
            toc: source.toc,
            progressFraction: source.progressFraction,
            lastOpenedAt: source.lastOpenedAt,
            importedAt: source.importedAt,
            isFinished: source.isFinished,
            readingPosition: source.readingPosition,
            bookmarks: source.bookmarks,
            annotations: source.annotations,
            isHiddenFromContinueReading: source.isHiddenFromContinueReading
        )
        book.canonicalID = source.canonicalID
        book.metadataModifiedAt = source.metadataModifiedAt
        book.progressModifiedAt = source.progressModifiedAt
        book.storageRoot = destStore.rootURL
        try copyFiles(from: source, sourceStore: sourceStore, to: book, destStore: destStore, replaceFolder: true)
        return book
    }

    private static func mergeBook(
        dest: BookSummary,
        source: BookSummary,
        sourceStore: LibraryStore,
        destStore: LibraryStore
    ) throws -> BookSummary {
        var book = dest
        book.bookmarks = mergeBookmarks(dest: dest.bookmarks, source: source.bookmarks)
        book.annotations = mergeAnnotations(dest: dest.annotations, source: source.annotations)
        book.isFinished = dest.isFinished || source.isFinished
        if newerProgress(source, than: dest) {
            book.progressFraction = source.progressFraction
            book.readingPosition = source.readingPosition
            book.lastOpenedAt = source.lastOpenedAt
            book.progressModifiedAt = source.progressModifiedAt
        }
        book.storageRoot = destStore.rootURL
        try copyFiles(from: source, sourceStore: sourceStore, to: book, destStore: destStore, replaceFolder: false)
        return book
    }

    private static func copyFiles(
        from source: BookSummary,
        sourceStore: LibraryStore,
        to dest: BookSummary,
        destStore: LibraryStore,
        replaceFolder: Bool
    ) throws {
        let fileManager = FileManager.default
        let destFolder = destStore.bookFolderURL(for: dest.id)
        if replaceFolder || !destStore.isDownloaded(dest) {
            if sourceStore.isDownloaded(source) {
                if fileManager.fileExists(atPath: destFolder.path) { try fileManager.removeItem(at: destFolder) }
                try fileManager.createDirectory(at: destFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: source.folderURL, to: destFolder)
            }
        }
        let sourceArchive = sourceStore.archiveURL(for: source)
        let destArchive = destStore.archiveURL(for: dest)
        if fileManager.fileExists(atPath: sourceArchive.path), !fileManager.fileExists(atPath: destArchive.path) {
            try destStore.preserveArchive(sourceArchive, for: dest)
        }
        if let canonicalID = dest.canonicalID ?? source.canonicalID {
            let sourceCover = sourceStore.cachedCoverURL(for: canonicalID)
            let destCover = destStore.cachedCoverURL(for: canonicalID)
            if fileManager.fileExists(atPath: sourceCover.path), !fileManager.fileExists(atPath: destCover.path) {
                try fileManager.createDirectory(at: destCover.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceCover, to: destCover)
            }
        }
    }

    private static func mergeBookmarks(dest: [ReaderBookmark], source: [ReaderBookmark]) -> [ReaderBookmark] {
        var result = dest
        for bookmark in source {
            if let index = result.firstIndex(where: { $0.id == bookmark.id }) {
                if (bookmark.modifiedAt ?? .distantPast) > (result[index].modifiedAt ?? .distantPast) {
                    result[index] = bookmark
                }
                continue
            }
            if result.contains(where: { $0.matches(bookmark.position) }) { continue }
            result.append(bookmark)
        }
        return result
    }

    private static func mergeAnnotations(dest: [ReaderAnnotation], source: [ReaderAnnotation]) -> [ReaderAnnotation] {
        var result = dest
        for annotation in source {
            if let index = result.firstIndex(where: { $0.id == annotation.id }) {
                if (annotation.modifiedAt ?? .distantPast) > (result[index].modifiedAt ?? .distantPast) {
                    result[index] = annotation
                }
            } else {
                result.append(annotation)
            }
        }
        return result
    }

    private static func newerProgress(_ source: BookSummary, than dest: BookSummary) -> Bool {
        (source.progressModifiedAt ?? source.lastOpenedAt ?? .distantPast)
            > (dest.progressModifiedAt ?? dest.lastOpenedAt ?? .distantPast)
    }

    private static func appendEvents(_ events: [ReadingEvent], destBookID: UUID, into destEvents: inout [ReadingEvent]) -> Int {
        var existing = Set(destEvents.map(\.id))
        var added = 0
        for event in events {
            guard existing.insert(event.id).inserted else { continue }
            destEvents.append(ReadingEvent(id: event.id, bookID: destBookID, day: event.day, hour: event.hour, seconds: event.seconds))
            added += 1
        }
        return added
    }
}
