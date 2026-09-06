import Foundation
import XCTest
@testable import OBooks

private final class MemoryCredentials: SyncCredentialStorage {
    var token: String?
    func read() throws -> String? { token }
    func write(_ value: String) throws { token = value }
    func remove() throws { token = nil }
}

@MainActor
final class SyncTransportTests: XCTestCase {
    func testLiveCoordinatorSynchronizesLocalStoresAndRestarts() async throws {
        guard let address = ProcessInfo.processInfo.environment["OBOOKS_SYNC_TEST_URL"] else {
            throw XCTSkip("通过 just sync-integration 运行临时 Go 服务联调")
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        try writeArchiveFixture(source)
        try Data("<container><rootfiles><rootfile full-path=\"content.opf\"/></rootfiles></container>".utf8).write(to: source.appendingPathComponent("META-INF/container.xml"))
        try Data("<package><metadata><title>Coordinator</title></metadata><manifest><item id=\"chapter\" href=\"chapter.xhtml\" media-type=\"application/xhtml+xml\"/></manifest><spine><itemref idref=\"chapter\"/></spine></package>".utf8).write(to: source.appendingPathComponent("content.opf"))
        let epub = directory.appendingPathComponent("book.epub")
        try BookArchive.pack(folderURL: source, archiveURL: epub)
        let rootA = directory.appendingPathComponent("a")
        let rootB = directory.appendingPathComponent("b")
        let storeA = LibraryStore(rootURL: rootA)
        let imported = try EPUBImporter(store: storeA).importBook(from: epub)
        XCTAssertTrue(storeA.save([imported]))
        let credentialsA = MemoryCredentials()
        let credentialsB = MemoryCredentials()
        let a = AppModel(rootURL: rootA, credentials: credentialsA, observeLifecycle: false)
        let b = AppModel(rootURL: rootB, credentials: credentialsB, observeLifecycle: false)
        await a.sync.login(server: address, username: "alice", password: "a-long-test-password")
        XCTAssertNil(a.sync.lastError)
        await b.sync.login(server: address, username: "alice", password: "a-long-test-password")
        XCTAssertNil(b.sync.lastError)
        let remote = try XCTUnwrap(b.books.first(where: { $0.canonicalID == imported.canonicalID }))
        XCTAssertFalse(b.libraryStore.isDownloaded(remote))
        let downloaded = await b.sync.download(remote)
        XCTAssertTrue(downloaded, b.sync.lastError ?? "")
        XCTAssertTrue(b.libraryStore.isDownloaded(remote))
        let note = ReaderAnnotation(text: "原文", kind: "note", sectionIndex: 0, range: NSRange(location: 0, length: 3))
        a.updateAnnotations(bookID: imported.id, annotations: [note])
        a.updateProgress(bookID: imported.id, fraction: 0.7, position: ReadingPosition(spineID: "chapter", characterOffset: 3))
        a.toggleBookmark(bookID: imported.id, position: ReadingPosition(spineID: "chapter", characterOffset: 3), title: "章节", progressFraction: 0.7)
        a.readingStats.record(bookID: imported.id, from: Date(), duration: 45, calendar: .current)
        a.sync.localDataChanged()
        await a.sync.synchronize()
        await b.sync.synchronize()
        XCTAssertNil(a.sync.lastError)
        XCTAssertNil(b.sync.lastError)
        var updated = try XCTUnwrap(b.books.first(where: { $0.id == remote.id }))
        XCTAssertEqual(updated.annotations.count, 1)
        XCTAssertEqual(updated.bookmarks.count, 1)
        XCTAssertEqual(updated.progressFraction, 0.7)
        XCTAssertEqual(b.readingStats.events.filter { $0.bookID == remote.id }.reduce(0) { $0 + $1.seconds }, 45)
        a.updateAnnotations(bookID: imported.id, annotations: [ReaderAnnotation(id: note.id, text: "来自 A", kind: "note", sectionIndex: 0, range: note.range)])
        b.updateAnnotations(bookID: remote.id, annotations: [ReaderAnnotation(id: note.id, text: "来自 B", kind: "note", sectionIndex: 0, range: note.range)])
        await a.sync.synchronize()
        await b.sync.synchronize()
        XCTAssertNil(b.sync.lastError)
        updated = try XCTUnwrap(b.books.first(where: { $0.id == remote.id }))
        XCTAssertEqual(Set(updated.annotations.map(\.text)), ["来自 A", "来自 B"])
        XCTAssertEqual(b.sync.pendingCount, 0)
        let restarted = AppModel(rootURL: rootB, credentials: credentialsB, observeLifecycle: false)
        await restarted.sync.synchronize()
        XCTAssertNil(restarted.sync.lastError)
        XCTAssertEqual(restarted.readingStats.events.filter { $0.bookID == remote.id }.reduce(0) { $0 + $1.seconds }, 45)
        a.delete(try XCTUnwrap(a.books.first(where: { $0.id == imported.id })))
        await a.sync.synchronize()
        await restarted.sync.synchronize()
        XCTAssertNil(restarted.sync.lastError)
        XCTAssertFalse(restarted.books.contains(where: { $0.id == remote.id }))
        XCTAssertFalse(restarted.libraryStore.isDownloaded(remote))
        XCTAssertTrue(restarted.readingStats.events.filter { $0.bookID == remote.id }.isEmpty)
    }

    func testServerRequiresHTTPSExceptLoopback() throws {
        XCTAssertEqual(try SyncAPI.validateServer("https://example.com/"), URL(string: "https://example.com"))
        XCTAssertNoThrow(try SyncAPI.validateServer("http://127.0.0.1:8080"))
        XCTAssertThrowsError(try SyncAPI.validateServer("http://example.com"))
        XCTAssertThrowsError(try SyncAPI.validateServer("https://user:secret@example.com"))
        XCTAssertThrowsError(try SyncAPI.validateServer("https://example.com?token=x"))
    }

    func testLiveTwoDeviceRoundTrip() async throws {
        guard let address = ProcessInfo.processInfo.environment["OBOOKS_SYNC_TEST_URL"] else {
            throw XCTSkip("通过 just sync-integration 运行临时 Go 服务联调")
        }
        let server = try SyncAPI.validateServer(address)
        let credentialsA = MemoryCredentials()
        let credentialsB = MemoryCredentials()
        let a = SyncAPI(server: server, credentials: credentialsA)
        let b = SyncAPI(server: server, credentials: credentialsB)
        let deviceA = UUID().uuidString
        let deviceB = UUID().uuidString
        _ = try await a.login(username: "alice", password: "a-long-test-password", deviceID: deviceA, deviceName: "Swift A")
        _ = try await b.login(username: "alice", password: "a-long-test-password", deviceID: deviceB, deviceName: "Swift B")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("book")
        try writeArchiveFixture(folder)
        let archive = directory.appendingPathComponent("book.epub")
        try BookArchive.pack(folderURL: folder, archiveURL: archive)
        let id = try BookArchive.fingerprint(archiveURL: archive)
        let localBook = BookSummary(id: UUID(), title: "跨端测试", authors: [], sortTitle: "book", sourceFileName: "book.epub", folderName: "book", coverPath: nil,
            spine: [EPUBSpineItem(id: "chapter", href: "chapter.xhtml", title: "Chapter", linear: true)], toc: [], progressFraction: 0, lastOpenedAt: nil, importedAt: Date(timeIntervalSince1970: 1000))
        let book = SyncChange(deviceID: deviceA, entity: "book", entityID: id, bookID: id, modifiedAt: 1000, payload: SyncPayload(book: CloudBook(localBook)))
        _ = try await a.push([book])
        try await a.upload(archive, bookID: id, kind: "content", progress: { _ in })
        let first = try await b.pull(cursor: 0)
        XCTAssertEqual(first.changes.first(where: { $0.bookID == id && $0.entity == "book" })?.payload.book?.title, localBook.title)
        let downloaded = try await b.download(bookID: id, kind: "content", progress: { _ in })
        defer { try? FileManager.default.removeItem(at: downloaded) }
        XCTAssertEqual(try BookArchive.fingerprint(archiveURL: downloaded), id)

        let note = ReaderAnnotation(text: "原始笔记", kind: "note", sectionIndex: 0, range: NSRange(location: 0, length: 5))
        let createNote = SyncChange(deviceID: deviceA, entity: "annotation", entityID: note.id.uuidString, bookID: id, modifiedAt: 1100, payload: SyncPayload(annotation: note))
        _ = try await a.push([createNote])
        let initialNotePage = try await a.pull(cursor: first.cursor)
        let base = try XCTUnwrap(initialNotePage.changes.first?.revision)
        var editA = createNote
        editA.changeID = UUID().uuidString
        editA.baseRevision = base
        editA.payload.annotation = ReaderAnnotation(id: note.id, text: "设备 A 修改", kind: "note", sectionIndex: 0, range: note.range)
        editA.modifiedAt = 1200
        var editB = editA
        editB.changeID = UUID().uuidString
        editB.deviceID = deviceB
        editB.payload.annotation = ReaderAnnotation(id: note.id, text: "设备 B 修改", kind: "note", sectionIndex: 0, range: note.range)
        _ = try await a.push([editA])
        let conflict = try await b.push([editB])
        XCTAssertEqual(conflict.conflicts, 1)
        let retry = try await b.push([editB])
        XCTAssertEqual(retry.conflicts, 0)

        let position = CloudProgress(fraction: 0.8, position: ReadingPosition(spineID: "chapter", characterOffset: 100), lastOpenedAt: Date(timeIntervalSince1970: 2000))
        let latest = SyncChange(deviceID: deviceA, entity: "progress", entityID: id, bookID: id, modifiedAt: 2000, payload: SyncPayload(progress: position))
        _ = try await a.push([latest])
        var older = latest
        older.deviceID = deviceB
        older.changeID = UUID().uuidString
        older.modifiedAt = 1500
        older.payload.progress?.fraction = 0.1
        _ = try await b.push([older])
        let event = CloudReadingEvent(id: UUID(), day: ReadingDay(year: 2026, month: 9, day: 6), hour: 10, seconds: 45)
        let reading = SyncChange(deviceID: deviceA, entity: "readingEvent", entityID: event.id.uuidString, bookID: id, modifiedAt: 2000, payload: SyncPayload(readingEvent: event))
        _ = try await a.push([reading])
        _ = try await a.push([reading])
        let final = try await b.pull(cursor: 0)
        var journal = SyncJournal()
        journal.receive(final)
        let projection = SyncProjection.apply(journal: journal, books: [], events: [])
        XCTAssertEqual(projection.books.count, 1)
        XCTAssertEqual(projection.books[0].annotations.count, 2)
        XCTAssertEqual(projection.books[0].progressFraction, 0.8)
        XCTAssertEqual(projection.events.count, 1)
        XCTAssertEqual(projection.events[0].seconds, 45)

        // 新建 API 模拟进程重启, 只凭持久化 refresh token 恢复会话.
        let restarted = SyncAPI(server: server, credentials: credentialsA)
        let afterRestart = try await restarted.pull(cursor: final.cursor)
        XCTAssertTrue(afterRestart.changes.isEmpty)
        var deleted = book
        deleted.changeID = UUID().uuidString
        deleted.deletedAt = 3000
        deleted.modifiedAt = 3000
        _ = try await restarted.push([deleted])
        let deletion = try await b.pull(cursor: final.cursor)
        journal.receive(deletion)
        let empty = SyncProjection.apply(journal: journal, books: projection.books, events: projection.events)
        XCTAssertTrue(empty.books.isEmpty)
        XCTAssertTrue(empty.events.isEmpty)
        try await restarted.logout()
        XCTAssertNil(credentialsA.token)
    }
}
