import XCTest
@testable import OBooks

final class SpeechTextIndexTests: XCTestCase {
    func testSentencesPreserveUTF16RangesAcrossAttachmentsAndEmoji() {
        let text = "  第一段。你好😀！\n\u{FFFC}\nDr. Smith reads a book. It is good.\n没有标点的段落\n-----\n"
        let index = SpeechTextIndex(text: text)
        XCTAssertGreaterThanOrEqual(index.sentences.count, 4)
        for sentence in index.sentences {
            XCTAssertEqual((text as NSString).substring(with: sentence.range), sentence.text)
            XCTAssertFalse(sentence.text.contains("\u{FFFC}"))
            XCTAssertNotNil(sentence.text.rangeOfCharacter(from: .alphanumerics))
        }
        XCTAssertEqual(index.sentences.last?.text, "没有标点的段落")
        XCTAssertTrue(index.sentences.contains { $0.text.contains("Dr. Smith") },
            "language=\(index.language ?? "nil"), sentences=\(index.sentences.map(\.text))")
    }

    func testBlankAndAttachmentOnlyChaptersHaveNoSentences() {
        XCTAssertTrue(SpeechTextIndex(text: "\n \u{FFFC}\n---\n").sentences.isEmpty)
    }

    func testOffsetInsideSentenceAndWhitespaceUsesOriginalCoordinates() throws {
        let index = SpeechTextIndex(text: "  Hello world.\n\nNext paragraph.")
        XCTAssertEqual(index.sentence(at: 0), 0)
        XCTAssertEqual(index.sentence(at: 8), 0)
        let second = try XCTUnwrap(index.sentences.last)
        XCTAssertEqual(index.sentence(at: second.range.location - 1), second.id)
        XCTAssertNil(index.sentence(at: NSMaxRange(second.range)))
        XCTAssertNotEqual(index.sentences.first?.paragraph, second.paragraph)
    }
}
