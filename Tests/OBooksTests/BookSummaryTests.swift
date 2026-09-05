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
