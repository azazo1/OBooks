import Foundation
import XCTest
@testable import OBooks

final class BookSummaryTests: XCTestCase {
    func testCompletionIsManualAndPromptStartsAtNinetyFivePercent() {
        var book = makeBook(progressFraction: 0.949)
        XCTAssertFalse(book.isNearCompletion)
        XCTAssertFalse(book.isFinished)

        book.progressFraction = 0.95
        XCTAssertTrue(book.isNearCompletion)
        XCTAssertFalse(book.isFinished)

        book.progressFraction = 1
        XCTAssertTrue(book.isNearCompletion)
        XCTAssertFalse(book.isFinished)

        book.isFinished = true
        XCTAssertFalse(book.isNearCompletion)
    }

    func testLegacyBookDefaultsToUnfinishedAndFinishedStatePersists() throws {
        var book = makeBook(progressFraction: 1)
        book.isFinished = true
        let encoded = try JSONEncoder().encode(book)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let legacyObject = object
        object.removeValue(forKey: "isFinished")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacyBook = try JSONDecoder().decode(BookSummary.self, from: legacyData)
        XCTAssertFalse(legacyBook.isFinished)

        let restoredBook = try JSONDecoder().decode(BookSummary.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertTrue(restoredBook.isFinished)
    }

    func testReadingPositionRoundTrips() throws {
        var book = makeBook(progressFraction: 0.42)
        let position = ReadingPosition(spineID: "chapter-2", characterOffset: 1234, viewportOffset: 18.5)
        book.readingPosition = position

        let restored = try JSONDecoder().decode(BookSummary.self, from: JSONEncoder().encode(book))

        XCTAssertEqual(restored.readingPosition, position)
    }

    func testBookmarksKeepTheirPositionsWhenReadingMovesAndRoundTrip() throws {
        var book = makeBook(progressFraction: 0.1)
        let firstPosition = ReadingPosition(spineID: "chapter-0", characterOffset: 120, viewportOffset: 18.5)
        book.toggleBookmark(at: firstPosition, title: "第一章", progressFraction: 0.1)
        let firstBookmark = try XCTUnwrap(book.bookmarks.first)

        let secondPosition = ReadingPosition(spineID: "chapter-0", characterOffset: 960)
        book.readingPosition = secondPosition
        book.progressFraction = 0.2
        XCTAssertFalse(firstBookmark.matches(secondPosition))
        book.toggleBookmark(at: secondPosition, title: "第一章", progressFraction: 0.2)
        book.readingPosition = ReadingPosition(spineID: "chapter-1", characterOffset: 120)
        book.progressFraction = 0.5

        XCTAssertEqual(book.bookmarks.count, 2)
        XCTAssertEqual(book.bookmarks.last, firstBookmark)
        XCTAssertFalse(firstBookmark.matches(try XCTUnwrap(book.readingPosition)))
        let restored = try JSONDecoder().decode(BookSummary.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(restored.bookmarks, book.bookmarks)
        XCTAssertEqual(restored.bookmarks.last?.position, firstPosition)
        XCTAssertEqual(restored.bookmarks.first?.position, secondPosition)
    }

    func testTogglingBookmarkRemovesOnlyMatchingTextPosition() {
        var book = makeBook(progressFraction: 0.1)
        let firstPosition = ReadingPosition(spineID: "chapter-0", characterOffset: 120, viewportOffset: 18.5)
        let secondPosition = ReadingPosition(spineID: "chapter-0", characterOffset: 960)
        let thirdPosition = ReadingPosition(spineID: "chapter-1", characterOffset: 120)
        for position in [firstPosition, secondPosition, thirdPosition] {
            book.toggleBookmark(at: position, title: "章节", progressFraction: 0.1)
        }

        book.toggleBookmark(
            at: ReadingPosition(spineID: "chapter-0", characterOffset: 120, viewportOffset: 19),
            title: "章节", progressFraction: 0.1
        )

        XCTAssertEqual(book.bookmarks.map(\.position), [thirdPosition, secondPosition])
    }

    func testBookWithoutBookmarksDecodesWithEmptyCollection() throws {
        let encoded = try JSONEncoder().encode(makeBook(progressFraction: 0))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "bookmarks")

        let restored = try JSONDecoder().decode(
            BookSummary.self, from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(restored.bookmarks.isEmpty)
    }

    func testMalformedReadingPositionIsIgnored() throws {
        let book = makeBook(progressFraction: 0.42)
        let data = try JSONEncoder().encode(book)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["readingPosition"] = ["spineID": 42, "characterOffset": "invalid"]

        let restored = try JSONDecoder().decode(
            BookSummary.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(restored.readingPosition)
    }

    func testOverlappingHighlightsMergeTheirTextAndRange() {
        let first = ReaderAnnotation(text: "AB", kind: "highlight", sectionIndex: 0, range: NSRange(location: 0, length: 2))
        let merged = ReaderAnnotation.mergedHighlight(
            text: "BC", sectionIndex: 0, range: NSRange(location: 1, length: 2), into: [first])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "ABC")
        XCTAssertEqual(merged[0].range, NSRange(location: 0, length: 3))
    }

    func testAnnotationsRoundTripAndLegacyDataDefaultsToEmpty() throws {
        var book = makeBook(progressFraction: 0)
        book.annotations = [ReaderAnnotation(
            text: "Marked", kind: "highlight", sectionIndex: 0, range: NSRange(location: 4, length: 6)
        )]
        let restored = try JSONDecoder().decode(BookSummary.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(restored.annotations, book.annotations)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        object.removeValue(forKey: "annotations")
        let legacy = try JSONDecoder().decode(
            BookSummary.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertTrue(legacy.annotations.isEmpty)
    }

    private func makeBook(progressFraction: Double) -> BookSummary {
        BookSummary(
            id: UUID(),
            title: "Test Book",
            authors: [],
            sortTitle: "test book",
            sourceFileName: "test.epub",
            folderName: UUID().uuidString,
            coverPath: nil,
            spine: [],
            toc: [],
            progressFraction: progressFraction,
            lastOpenedAt: nil,
            importedAt: Date()
        )
    }
}
