import Foundation

enum SyncProjection {
    static func capture(books: [BookSummary], events: [ReadingEvent], journal: inout SyncJournal, now: Date) {
        let grouped = Dictionary(grouping: events, by: \.bookID)
        for book in books {
            guard let id = book.canonicalID else { continue }
            journal.capture(entity: "book", entityID: id, bookID: id, payload: SyncPayload(book: CloudBook(book)), modifiedAt: book.metadataModifiedAt ?? book.importedAt)
            if book.lastOpenedAt != nil || book.readingPosition != nil {
                journal.capture(entity: "progress", entityID: id, bookID: id,
                    payload: SyncPayload(progress: CloudProgress(fraction: book.progressFraction, position: book.readingPosition, lastOpenedAt: book.lastOpenedAt)),
                    modifiedAt: book.progressModifiedAt ?? book.lastOpenedAt ?? book.importedAt)
            }
            for bookmark in book.bookmarks {
                journal.capture(entity: "bookmark", entityID: bookmark.id.uuidString, bookID: id,
                    payload: SyncPayload(bookmark: bookmark), modifiedAt: bookmark.modifiedAt ?? book.importedAt)
            }
            for annotation in book.annotations {
                journal.capture(entity: "annotation", entityID: annotation.id.uuidString, bookID: id,
                    payload: SyncPayload(annotation: annotation), modifiedAt: annotation.modifiedAt ?? book.importedAt)
            }
            let keys = Set(book.bookmarks.map { "bookmark:" + $0.id.uuidString.lowercased() } + book.annotations.map { "annotation:" + $0.id.uuidString.lowercased() })
            let existingKeys = Set(journal.localPayloads.keys)
            for key in existingKeys {
                guard let existing = journal.effective(key), existing.bookID == id,
                      existing.entity == "bookmark" || existing.entity == "annotation",
                      existing.deletedAt == nil, !keys.contains(key) else { continue }
                journal.enqueue(entity: existing.entity, entityID: existing.entityID, bookID: id, payload: SyncPayload(), modifiedAt: now, deleted: true)
                journal.localPayloads.removeValue(forKey: key)
            }
            for event in grouped[book.id] ?? [] {
                journal.capture(entity: "readingEvent", entityID: event.id.uuidString, bookID: id,
                    payload: SyncPayload(readingEvent: CloudReadingEvent(id: event.id, day: event.day, hour: event.hour, seconds: event.seconds)), modifiedAt: now)
            }
        }
    }

    static func recordVisibleState(books: [BookSummary], journal: inout SyncJournal) {
        let bookIDs = Set(books.compactMap(\.canonicalID))
        var effective = journal.records
        for change in journal.pending { effective[change.key] = change }
        let visible = effective.filter { $0.value.deletedAt == nil && bookIDs.contains($0.value.bookID) }
        journal.localPayloads = visible.mapValues(\.payload)
        journal.localRevisions = visible.mapValues { $0.revision == 0 ? $0.baseRevision : $0.revision }
    }

    static func apply(journal: SyncJournal, books: [BookSummary], events: [ReadingEvent]) -> (books: [BookSummary], events: [ReadingEvent], removed: [BookSummary]) {
        var result = books
        var resultEvents = events
        var removed: [BookSummary] = []
        var effective = journal.records
        for change in journal.pending { effective[change.key] = change }
        let records = effective.values.sorted {
            $0.revision == $1.revision ? $0.key < $1.key : $0.revision < $1.revision
        }
        for record in records where record.entity == "book" {
            if record.deletedAt != nil {
                let deleting = result.filter { $0.canonicalID == record.bookID }
                removed += deleting
                let ids = Set(deleting.map(\.id))
                result.removeAll { ids.contains($0.id) }
                resultEvents.removeAll { ids.contains($0.bookID) }
            } else if let payload = record.payload.book {
                if let index = result.firstIndex(where: { $0.canonicalID == record.bookID }) {
                    let original = result[index]
                    var replacement = payload.localBook(id: original.id, canonicalID: record.bookID)
                    replacement.folderName = original.folderName
                    replacement.storageRoot = original.storageRoot
                    replacement.bookmarks = original.bookmarks
                    replacement.annotations = original.annotations
                    replacement.progressFraction = original.progressFraction
                    replacement.readingPosition = original.readingPosition
                    replacement.lastOpenedAt = original.lastOpenedAt
                    replacement.progressModifiedAt = original.progressModifiedAt
                    replacement.metadataModifiedAt = Date(timeIntervalSince1970: record.modifiedAt)
                    result[index] = replacement
                } else {
                    var book = payload.localBook(canonicalID: record.bookID)
                    book.metadataModifiedAt = Date(timeIntervalSince1970: record.modifiedAt)
                    result.append(book)
                }
            }
        }
        for record in records where record.entity != "book" {
            guard let index = result.firstIndex(where: { $0.canonicalID == record.bookID }) else { continue }
            let deleted = record.deletedAt != nil
            switch record.entity {
            case "progress":
                if !deleted, let progress = record.payload.progress {
                    result[index].progressFraction = progress.fraction
                    result[index].readingPosition = progress.position
                    result[index].lastOpenedAt = progress.lastOpenedAt
                    result[index].progressModifiedAt = Date(timeIntervalSince1970: record.modifiedAt)
                }
            case "bookmark":
                result[index].bookmarks.removeAll { $0.id.uuidString.lowercased() == record.entityID.lowercased() }
                if !deleted, let bookmark = record.payload.bookmark { result[index].bookmarks.insert(bookmark, at: 0) }
            case "annotation":
                result[index].annotations.removeAll { $0.id.uuidString.lowercased() == record.entityID.lowercased() }
                if !deleted, let annotation = record.payload.annotation { result[index].annotations.insert(annotation, at: 0) }
            case "readingEvent":
                resultEvents.removeAll { $0.id.uuidString.lowercased() == record.entityID.lowercased() }
                if !deleted, let event = record.payload.readingEvent {
                    resultEvents.append(ReadingEvent(id: event.id, bookID: result[index].id, day: event.day, hour: event.hour, seconds: event.seconds))
                }
            default: break
            }
        }
        result.sort { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        return (result, resultEvents, removed)
    }
}
