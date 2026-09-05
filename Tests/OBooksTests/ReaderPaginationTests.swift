import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderPaginationTests: XCTestCase {
    func testPagesCoverEveryCharacterOnceAndUseExactViewportSteps() throws {
        for columns in [1, 2] {
            let view = makeTextView()
            view.configurePageColumns(columns, viewportHeight: 600)
            let manager = try XCTUnwrap(view.layoutManager)
            XCTAssertGreaterThan(view.pageCount, 2)
            var end = 0
            for (index, container) in manager.textContainers.enumerated() {
                let range = manager.characterRange(
                    forGlyphRange: manager.glyphRange(for: container), actualGlyphRange: nil
                )
                XCTAssertEqual(range.location, end)
                XCTAssertGreaterThan(range.length, 0)
                XCTAssertEqual(view.pageOffset(forCharacter: range.location), CGFloat(index / columns) * 600)
                end = NSMaxRange(range)
                XCTAssertLessThanOrEqual(manager.usedRect(for: container).maxY, container.size.height + 1)
            }
            XCTAssertEqual(end, view.string.utf16.count)
            XCTAssertEqual(view.frame.height, CGFloat(view.pageCount) * 600)
            XCTAssertEqual(view.pageOffset(forCharacter: end), CGFloat(view.pageCount - 1) * 600)
        }
    }

    func testReturningToScrollingRestoresUnboundedTextContainer() throws {
        let view = makeTextView()
        view.configurePageColumns(2, viewportHeight: 600)
        view.configurePageColumns(0, viewportHeight: 600)
        view.updateDocumentHeight(minimumHeight: 600)
        let manager = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        XCTAssertEqual(manager.textContainers.count, 1)
        XCTAssertEqual(manager.glyphRange(for: container).length, manager.numberOfGlyphs)
        XCTAssertGreaterThan(view.frame.height, 600)
        XCTAssertNil(view.pageOffset(forCharacter: 100))
    }

    func testLargeIllustrationFitsPageAndKeepsFollowingText() throws {
        let view = makeTextView()
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: NSSize(width: 1200, height: 2400))
        attachment.bounds = NSRect(x: 0, y: 0, width: 720, height: 1440)
        let content = NSMutableAttributedString(attachment: attachment)
        content.append(NSAttributedString(string: "\n" + view.string, attributes: [.font: NSFont.systemFont(ofSize: 18)]))
        view.textStorage?.setAttributedString(content)
        view.configurePageColumns(2, viewportHeight: 600)
        let manager = try XCTUnwrap(view.layoutManager)
        let last = try XCTUnwrap(manager.textContainers.last)
        XCTAssertLessThan(attachment.bounds.height, 472)
        XCTAssertEqual(attachment.bounds.width / attachment.bounds.height, 0.5, accuracy: 0.001)
        XCTAssertEqual(NSMaxRange(manager.glyphRange(for: last)), manager.numberOfGlyphs)
    }

    func testDragDistanceIsProportionalToPageWidthAndCanReverse() {
        var gesture = ReaderPageTurnGesture()
        gesture.update(delta: -3, timestamp: 1)
        XCTAssertNil(gesture.direction)
        gesture.update(delta: -197, timestamp: 1.2)
        XCTAssertEqual(gesture.direction, 1)
        XCTAssertEqual(gesture.progress(direction: 1, extent: 800), 0.25)
        XCTAssertTrue(gesture.shouldCommit(direction: 1, extent: 800, timestamp: 1.4))
        gesture.update(delta: 30, timestamp: 1.41)
        gesture.update(delta: 30, timestamp: 1.43)
        XCTAssertFalse(gesture.shouldCommit(direction: 1, extent: 800, timestamp: 1.44))
        gesture.update(delta: 200, timestamp: 1.45)
        XCTAssertEqual(gesture.progress(direction: 1, extent: 800), 0)
    }

    func testFlickCommitsButPausingBeforeReleaseDoesNot() {
        var gesture = ReaderPageTurnGesture()
        gesture.update(delta: -10, timestamp: 1)
        gesture.update(delta: -30, timestamp: 1.02)
        XCTAssertTrue(gesture.shouldCommit(direction: 1, extent: 900, timestamp: 1.03))
        XCTAssertFalse(gesture.shouldCommit(direction: 1, extent: 900, timestamp: 1.4))
        XCTAssertFalse(gesture.shouldCommit(direction: -1, extent: 900, timestamp: 1.03))
    }

    private func makeTextView() -> ReaderTextView {
        let view = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view.isEditable = false
        view.setReadingInsets(horizontal: 56, vertical: 64)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.6
        view.textStorage?.setAttributedString(NSAttributedString(
            string: String(repeating: "中文阅读分页与 English words, 12345.\n", count: 180),
            attributes: [.font: NSFont.systemFont(ofSize: 18), .paragraphStyle: paragraph]
        ))
        return view
    }
}
