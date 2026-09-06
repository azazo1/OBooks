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
                XCTAssertTrue(fixture.scrollView.isPageTransitionActive || !fixture.scrollView.canAnimateContentTransitions)
                fixture.scrollView.prepareForProgrammaticScroll()
                XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 600)
                XCTAssertFalse(fixture.textView.isHidden)
                fixture.coordinator.showSpeechRange(NSRange(location: 0, length: 3))
                fixture.scrollView.prepareForProgrammaticScroll()
                XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 0)
            }
        }
    }

    func testSpeechRevealOnSamePageSnapsWithoutPageTransition() throws {
        for columns in [1, 2] {
            let fixture = Fixture(columns: columns)
            defer { fixture.close() }
            let manager = try XCTUnwrap(fixture.textView.layoutManager)
            let right = manager.characterRange(
                forGlyphRange: manager.glyphRange(for: manager.textContainers[columns - 1]),
                actualGlyphRange: nil
            )
            fixture.scrollView.scroll(to: 12, animated: false)
            fixture.coordinator.showSpeechRange(NSRange(location: 0, length: 3))
            XCTAssertFalse(fixture.scrollView.isPageTransitionActive)
            XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 0, accuracy: 1)

            fixture.scrollView.scroll(to: 12, animated: false)
            fixture.coordinator.showSpeechRange(NSRange(location: right.location, length: 3))
            XCTAssertFalse(fixture.scrollView.isPageTransitionActive)
            XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 0, accuracy: 1)
        }
    }

    func testHiddenWindowSpeechTurnAppliesImmediatelyWithoutTransition() throws {
        for columns in [1, 2] {
            let fixture = Fixture(columns: columns)
            defer { fixture.close() }
            fixture.window.orderOut(nil)
            let manager = try XCTUnwrap(fixture.textView.layoutManager)
            let range = manager.characterRange(
                forGlyphRange: manager.glyphRange(for: manager.textContainers[columns]),
                actualGlyphRange: nil
            )
            fixture.coordinator.showSpeechRange(NSRange(location: range.location, length: 3))
            XCTAssertFalse(fixture.scrollView.isPageTransitionActive)
            XCTAssertFalse(fixture.textView.isHidden)
            XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, 600)
        }
    }

    func testWindowBecamePresentableRevealsOnlyWhileFollowing() async {
        let engine = FakeSpeechEngine()
        let session = SpeechSession(engine: engine)
        let bridge = ReaderSpeechBridge(session: session)
        let frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scrollView = ReaderScrollView(frame: frame)
        let textView = ReaderTextView(frame: frame)
        window.contentView = scrollView
        scrollView.documentView = textView
        bridge.attach(textView: textView, scrollView: scrollView)
        defer {
            bridge.teardown()
            window.close()
        }
        window.orderFrontRegardless()
        var revealed = 0
        bridge.reveal = { _ in revealed += 1 }
        session.configure(spineIDs: ["chapter"], title: { _ in "t" }, loadText: { _ in "Hello world." })
        session.start(section: 0)
        for _ in 0..<100 where session.state != .playing {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(session.state, .playing)
        bridge.follow.resumeNow()
        XCTAssertTrue(bridge.follow.isFollowing)
        for _ in 0..<50 where !window.occlusionState.contains(.visible) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        revealed = 0
        bridge.handleWindowBecamePresentable()
        XCTAssertEqual(revealed, 1)

        bridge.follow.userInteraction()
        bridge.handleWindowBecamePresentable()
        XCTAssertEqual(revealed, 1)
    }

    func testInterruptSpeechNavigationCommitsPendingScroll() {
        let fixture = Fixture(columns: 1)
        defer { fixture.close() }
        fixture.scrollView.configure(flow: .scrolling(scope: .chapter))
        fixture.textView.configurePageColumns(0, viewportHeight: 600)
        fixture.textView.updateDocumentHeight(minimumHeight: 600)
        fixture.scrollView.scroll(to: 240, animated: true, forSpeech: true)
        let expected = fixture.scrollView.scrollTargetY ?? fixture.scrollView.contentView.bounds.minY
        fixture.scrollView.interruptSpeechNavigation()
        XCTAssertEqual(fixture.scrollView.contentView.bounds.minY, expected, accuracy: 1)
        XCTAssertNil(fixture.scrollView.scrollTargetY)
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
