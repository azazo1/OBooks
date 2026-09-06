import Foundation
import XCTest
@testable import OBooks

final class SyncTests: XCTestCase {
    private let canonicalID = String(repeating: "a", count: 64)

    func testArchiveIdentityIgnoresCompressionAndRejectsChangedContent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("book")
        try writeArchiveFixture(folder)
        let first = directory.appendingPathComponent("first.epub")
        let second = directory.appendingPathComponent("second.epub")
        try BookArchive.pack(folderURL: folder, archiveURL: first)
        try BookArchive.pack(folderURL: folder, archiveURL: second)
        let fingerprint = try BookArchive.fingerprint(folderURL: folder)
        XCTAssertEqual(try BookArchive.fingerprint(archiveURL: first), fingerprint)
        XCTAssertEqual(try BookArchive.fingerprint(archiveURL: second), fingerprint)
        try Data("changed".utf8).write(to: folder.appendingPathComponent("chapter.xhtml"))
        XCTAssertNotEqual(try BookArchive.fingerprint(folderURL: folder), fingerprint)
        for path in ["../private", "/private", "a/../b", "a\\b", "a//b", "./a"] {
            XCTAssertThrowsError(try BookArchive.validatePath(path))
        }
        XCTAssertThrowsError(try BookArchive.unpack(archiveURL: first, destination: directory.appendingPathComponent("wrong"), expectedID: String(repeating: "0", count: 64)))
    }

    func testLibraryAndStatsMigrateWithoutLosingIdentity() throws {
        let book = makeBook()
        let legacy = LibrarySnapshot(schemaVersion: 1, books: [book])
        let migrated = try LibraryMigration.decode(JSONEncoder().encode(legacy))
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.books, [book])
        XCTAssertThrowsError(try LibraryMigration.decode(JSONEncoder().encode(LibrarySnapshot(schemaVersion: 99, books: []))))
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bucket = ReadingTimeBucket(bookID: book.id, day: ReadingDay(year: 2026, month: 9, day: 6), hour: 10, seconds: 300)
        struct Legacy: Encodable { var schemaVersion = 1; var buckets: [ReadingTimeBucket] }
        try JSONEncoder().encode(Legacy(buckets: [bucket])).write(to: directory.appendingPathComponent("reading-stats.json"))
        let store = ReadingStatsStore(rootURL: directory)
        let first = store.loadEvents()
        XCTAssertEqual(store.loadEvents(), first)
        XCTAssertEqual(first.first?.seconds, 300)
        let ledger = ReadingStatsLedger()
        ledger.replaceEvents(first + first)
        XCTAssertEqual(ledger.buckets.first?.seconds, 300)
    }

    func testJournalPersistsOperationsAndOnlyRebasesUnsentEdits() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SyncJournalStore(rootURL: directory)
        var journal = SyncJournal()
        journal.enqueue(entity: "progress", entityID: canonicalID, bookID: canonicalID, payload: SyncPayload(progress: CloudProgress(fraction: 0.2)), modifiedAt: Date(timeIntervalSince1970: 1000))
        journal.enqueue(entity: "progress", entityID: canonicalID, bookID: canonicalID, payload: SyncPayload(progress: CloudProgress(fraction: 0.3)), modifiedAt: Date(timeIntervalSince1970: 2000))
        try store.save(journal)
        XCTAssertEqual(try store.load().pending, journal.pending)
        XCTAssertEqual(journal.batch().count, 1)
        let sent = journal.batch()[0]
        var acknowledged = sent
        acknowledged.revision = 5
        journal.receive(SyncPull(changes: [acknowledged], cursor: 5, hasMore: false, serverTime: 3000))
        journal.acknowledge([sent.changeID])
        journal.rebaseUnsent(after: [sent])
        XCTAssertEqual(journal.pending.first?.baseRevision, 5)
        XCTAssertEqual(journal.pending.first?.payload.progress?.fraction, 0.3)
        try store.save(journal)
        XCTAssertEqual(try store.load().cursor, 5)
    }

    func testClockCalibrationPreservesAttemptedOperationIdentity() {
        var journal = SyncJournal()
        journal.enqueue(entity: "progress", entityID: canonicalID, bookID: canonicalID, payload: SyncPayload(progress: CloudProgress(fraction: 0.2)), modifiedAt: Date(timeIntervalSince1970: 10000))
        let attempted = journal.pending[0]
        journal.attemptedIDs.insert(attempted.changeID)
        journal.enqueue(entity: "progress", entityID: canonicalID, bookID: canonicalID, payload: SyncPayload(progress: CloudProgress(fraction: 0.3)), modifiedAt: Date(timeIntervalSince1970: 11000))
        XCTAssertTrue(journal.calibrateClock(serverTime: 1000, localTime: 12000))
        XCTAssertEqual(journal.pending[0], attempted)
        XCTAssertEqual(journal.pending[1].modifiedAt, 0)
    }

    func testRemoteProjectionPreservesPendingEditAndAppliesConflictCopy() throws {
        var book = makeBook()
        book.canonicalID = canonicalID
        var journal = SyncJournal()
        SyncProjection.capture(books: [book], events: [], journal: &journal, now: Date(timeIntervalSince1970: 1000))
        let initial = journal.pending[0]
        var remote = initial
        remote.revision = 1
        journal.records[remote.key] = remote
        journal.pending = []
        let note = ReaderAnnotation(text: "local", kind: "note", sectionIndex: 0, range: NSRange(location: 1, length: 2))
        book.annotations = [note]
        SyncProjection.capture(books: [book], events: [], journal: &journal, now: Date(timeIntervalSince1970: 1001))
        var cloudNote = journal.pending.first(where: { $0.entity == "annotation" })!
        cloudNote.payload.annotation = ReaderAnnotation(id: note.id, text: "remote", kind: "note", sectionIndex: 0, range: note.range)
        cloudNote.revision = 2
        journal.records[cloudNote.key] = cloudNote
        let projection = SyncProjection.apply(journal: journal, books: [book], events: [])
        XCTAssertEqual(projection.books[0].annotations.first?.text, "local")
        journal.pending = []
        var copy = ReaderAnnotation(text: "local", kind: "note", sectionIndex: 0, range: note.range)
        copy.conflictOf = note.id.uuidString
        let copyChange = SyncChange(deviceID: "B", entity: "annotation", entityID: copy.id.uuidString, bookID: canonicalID, revision: 3, modifiedAt: 1001, conflictOf: note.id.uuidString, payload: SyncPayload(annotation: copy))
        journal.records[copyChange.key] = copyChange
        let merged = SyncProjection.apply(journal: journal, books: [book], events: [])
        XCTAssertEqual(Set(merged.books[0].annotations.map(\.text)), ["local", "remote"])
        XCTAssertEqual(merged.books[0].annotations.filter { $0.conflictOf != nil }.count, 1)
        SyncProjection.capture(books: merged.books, events: [], journal: &journal, now: Date())
        XCTAssertTrue(journal.pending.isEmpty)
    }

    func testRemoteDeletionRemovesBookAndEventsAndSurvivesRestart() {
        var book = makeBook()
        book.canonicalID = canonicalID
        let change = SyncChange(deviceID: "B", entity: "book", entityID: canonicalID, bookID: canonicalID, revision: 1, modifiedAt: 1000, deletedAt: 1000, payload: SyncPayload())
        var journal = SyncJournal()
        journal.records[change.key] = change
        let event = ReadingEvent(id: UUID(), bookID: book.id, day: ReadingDay(year: 2026, month: 9, day: 6), hour: 10, seconds: 30)
        let projection = SyncProjection.apply(journal: journal, books: [book], events: [event])
        XCTAssertTrue(projection.books.isEmpty)
        XCTAssertTrue(projection.events.isEmpty)
        XCTAssertEqual(projection.removed, [book])
    }

    func testLocalEditDuringPagedPullDoesNotDeleteUnseenRemoteNote() {
        var book = makeBook()
        book.canonicalID = canonicalID
        var journal = SyncJournal()
        SyncProjection.capture(books: [book], events: [], journal: &journal, now: Date())
        let known = ReaderAnnotation(text: "尚未变化", kind: "note", sectionIndex: 0, range: NSRange(location: 4, length: 1))
        book.annotations = [known]
        SyncProjection.capture(books: [book], events: [], journal: &journal, now: Date())
        journal.pending = []
        let unseen = ReaderAnnotation(text: "另一设备", kind: "note", sectionIndex: 0, range: NSRange(location: 0, length: 1))
        let change = SyncChange(deviceID: "remote", entity: "annotation", entityID: unseen.id.uuidString, bookID: canonicalID, revision: 10, modifiedAt: 1000, payload: SyncPayload(annotation: unseen))
        journal.receive(SyncPull(changes: [change], cursor: 10, hasMore: true, serverTime: 1000))
        var remoteEdit = change
        remoteEdit.entityID = known.id.uuidString
        remoteEdit.payload.annotation = ReaderAnnotation(id: known.id, text: "远端修改", kind: "note", sectionIndex: 0, range: known.range)
        journal.records[remoteEdit.key] = remoteEdit
        book.progressFraction = 0.4
        book.lastOpenedAt = Date()
        SyncProjection.capture(books: [book], events: [], journal: &journal, now: Date())
        XCTAssertFalse(journal.pending.contains(where: { $0.key == change.key }))
        XCTAssertFalse(journal.pending.contains(where: { $0.key == remoteEdit.key }))
        book.annotations = [ReaderAnnotation(id: known.id, text: "本地编辑", kind: "note", sectionIndex: 0, range: known.range)]
        SyncProjection.capture(books: [book], events: [], journal: &journal, now: Date())
        XCTAssertEqual(journal.pending.first(where: { $0.key == remoteEdit.key })?.baseRevision, 0)
    }

    func testCloudPositionAndAnnotationWireFormat() throws {
        let annotation = ReaderAnnotation(text: "文字", kind: "note", sectionIndex: 0, range: NSRange(location: 12, length: 3))
        let data = try SyncCoding.encoder().encode(SyncPayload(annotation: annotation))
        XCTAssertEqual(try SyncCoding.decoder().decode(SyncPayload.self, from: data).annotation, annotation)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encoded = try XCTUnwrap(object["annotation"] as? [String: Any])
        XCTAssertEqual(encoded["range"] as? [Int], [12, 3])
    }

    private func makeBook() -> BookSummary {
        BookSummary(id: UUID(), title: "Book", authors: [], sortTitle: "book", sourceFileName: "book.epub", folderName: "local", coverPath: nil,
            spine: [EPUBSpineItem(id: "chapter", href: "chapter.xhtml", title: "Chapter", linear: true)], toc: [], progressFraction: 0, lastOpenedAt: nil, importedAt: Date(timeIntervalSince1970: 1000))
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("obooks-sync-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeArchiveFixture(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
    try Data("application/epub+zip".utf8).write(to: directory.appendingPathComponent("mimetype"))
    try Data("<container/>".utf8).write(to: directory.appendingPathComponent("META-INF/container.xml"))
    try Data("<p>hello</p>".utf8).write(to: directory.appendingPathComponent("chapter.xhtml"))
}
