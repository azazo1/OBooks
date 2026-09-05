import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderSpeechHighlightTests: XCTestCase {
    func testRightColumnSpeechHighlightRequestsRedrawOnEveryWordAndStop() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let manager = try XCTUnwrap(fixture.textView.layoutManager)
        let rightContainer = try XCTUnwrap(manager.textContainers.dropFirst().first)
        let characters = manager.characterRange(
            forGlyphRange: manager.glyphRange(for: rightContainer), actualGlyphRange: nil
        )
        let first = NSRange(location: characters.location + 2, length: 4)
        let second = NSRange(location: characters.location + 10, length: 4)
        fixture.display()
        fixture.coordinator.showSpeechRange(first)
        XCTAssertNotNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: first.location, effectiveRange: nil))
        XCTAssertTrue(fixture.textView.layer?.needsDisplay() == true)
        XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 0)

        fixture.display()
        fixture.coordinator.showSpeechRange(second)
        XCTAssertNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: first.location, effectiveRange: nil))
        XCTAssertNotNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: second.location, effectiveRange: nil))
        XCTAssertTrue(fixture.textView.layer?.needsDisplay() == true)
        XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 0)

        fixture.display()
        fixture.coordinator.execute(.stopSpeech)
        XCTAssertNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: second.location, effectiveRange: nil))
        XCTAssertTrue(fixture.textView.layer?.needsDisplay() == true)
    }

    func testSpeechHighlightFollowsColumnsAndTurnsPagesWithoutChangingSelection() throws {
        for columns in [1, 2] {
            let fixture = Fixture(columns: columns)
            defer { fixture.close() }
            let manager = try XCTUnwrap(fixture.textView.layoutManager)
            let selection = NSRange(location: 2, length: 5)
            fixture.textView.setSelectedRange(selection)
            var previous: NSRange?
            for index in 0..<(columns * 2) {
                let characters = manager.characterRange(
                    forGlyphRange: manager.glyphRange(for: manager.textContainers[index]), actualGlyphRange: nil
                )
                let range = NSRange(location: characters.location + 2, length: 4)
                fixture.display()
                fixture.coordinator.showSpeechRange(range)
                XCTAssertNotNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: range.location, effectiveRange: nil))
                if let previous {
                    XCTAssertNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: previous.location, effectiveRange: nil))
                }
                XCTAssertTrue(fixture.textView.layer?.needsDisplay() == true)
                XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, CGFloat(index / columns) * 600)
                XCTAssertEqual(fixture.textView.selectedRange(), selection)
                previous = range
            }
        }
    }

    func testProgrammaticSpeechTurnUsesAnimationForBothDirectionsAndColumns() throws {
        for columns in [1, 2] {
            for orientation in ReaderPageOrientation.allCases {
                let fixture = Fixture(columns: columns)
                defer { fixture.close() }
                fixture.scrollView.configure(flow: .paging(orientation: orientation, columns: columns == 1 ? .single : .double))
                let manager = try XCTUnwrap(fixture.textView.layoutManager)
                let range = manager.characterRange(forGlyphRange: manager.glyphRange(for: manager.textContainers[columns]), actualGlyphRange: nil)
                fixture.coordinator.showSpeechRange(NSRange(location: range.location, length: 3))
                XCTAssertTrue(fixture.scrollView.isPageTransitionActive || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                fixture.scrollView.prepareForProgrammaticScroll()
                XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 600)
                XCTAssertFalse(fixture.textView.isHidden)
                fixture.coordinator.showSpeechRange(NSRange(location: 0, length: 3))
                fixture.scrollView.prepareForProgrammaticScroll()
                XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 0)
            }
        }
    }

    @MainActor
    private final class Fixture {
        let coordinator = NativeReaderView.Coordinator()
        let window: NSWindow
        let scrollView: ReaderScrollView
        let textView: ReaderTextView

        init(columns: Int = 2) {
            _ = NSApplication.shared
            let frame = NSRect(x: 0, y: 0, width: 900, height: 600)
            window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            scrollView = ReaderScrollView(frame: frame)
            textView = ReaderTextView(frame: frame)
            window.contentView = scrollView
            scrollView.wantsLayer = true
            scrollView.contentView.wantsLayer = true
            textView.wantsLayer = true
            textView.isEditable = false
            textView.isSelectable = true
            textView.isHorizontallyResizable = false
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.documentView = textView
            scrollView.configure(flow: .paging(orientation: .horizontal, columns: columns == 1 ? .single : .double))
            textView.setReadingInsets(horizontal: 56, vertical: 64)
            textView.textStorage?.setAttributedString(NSAttributedString(
                string: String(repeating: "朗读高亮测试 Reading highlight.\n", count: 180),
                attributes: [.font: NSFont.systemFont(ofSize: 18)]
            ))
            textView.configurePageColumns(columns, viewportHeight: 600)
            coordinator.attach(scrollView: scrollView, textView: textView)
            window.orderFrontRegardless()
        }

        func display() {
            window.displayIfNeeded()
            textView.layer?.displayIfNeeded()
            XCTAssertFalse(textView.needsDisplay)
            XCTAssertFalse(textView.layer?.needsDisplay() ?? true)
        }

        func close() {
            coordinator.teardown()
            window.close()
        }
    }
}
