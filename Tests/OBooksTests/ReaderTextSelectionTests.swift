import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderTextSelectionTests: XCTestCase {
    func testPageColumnsReceiveMouseEventsThroughScrollView() throws {
        for columns in [1, 2] {
            for width: CGFloat in [900, 1180] {
                let fixture = Fixture(columns: columns, width: width)
                defer { fixture.window.close() }
                let manager = try XCTUnwrap(fixture.textView.layoutManager)
                for index in 0..<(columns * 2) {
                    fixture.scrollView.scroll(to: CGFloat(index / columns) * 600, animated: false)
                    let glyph = manager.glyphRange(for: manager.textContainers[index]).location + 2
                    let point = fixture.point(forGlyph: glyph, containerIndex: index)
                    XCTAssertTrue(try fixture.hitView(at: point) === fixture.textView,
                                  "columns=\(columns), container=\(index), width=\(width)")
                }
            }
        }
    }

    func testClickingBlankSpaceClearsDoubleColumnSelection() throws {
        let fixture = Fixture(columns: 2)
        defer { fixture.window.close() }
        let manager = try XCTUnwrap(fixture.textView.layoutManager)
        let rightRange = manager.glyphRange(for: manager.textContainers[1])
        let start = fixture.point(forGlyph: 2, containerIndex: 0)
        let end = fixture.point(forGlyph: rightRange.location + 10, containerIndex: 1)
        let target = try fixture.hitView(at: start)
        target.mouseDown(with: try fixture.event(.leftMouseDown, at: start))
        target.mouseDragged(with: try fixture.event(.leftMouseDragged, at: end))
        target.mouseUp(with: try fixture.event(.leftMouseUp, at: end))
        XCTAssertGreaterThan(NSMaxRange(fixture.textView.selectedRange()), rightRange.location)

        let blankPoint = NSPoint(x: end.x, y: 580)
        let blankTarget = try fixture.hitView(at: blankPoint)
        XCTAssertTrue(blankTarget === fixture.textView)
        blankTarget.mouseDown(with: try fixture.event(.leftMouseDown, at: blankPoint))
        blankTarget.mouseUp(with: try fixture.event(.leftMouseUp, at: blankPoint))

        XCTAssertEqual(fixture.textView.selectedRange().length, 0)
    }

    func testMouseDragSelectsTextInEachPageColumn() throws {
        for width: CGFloat in [900, 1180] {
            let fixture = Fixture(columns: 2, width: width)
            defer { fixture.window.close() }
            let manager = try XCTUnwrap(fixture.textView.layoutManager)
            for containerIndex in 0..<4 {
                let container = manager.textContainers[containerIndex]
                let glyphRange = manager.glyphRange(for: container)
                let start = manager.characterIndexForGlyph(at: glyphRange.location + 2)
                let end = manager.characterIndexForGlyph(at: glyphRange.location + 10)
                fixture.scrollView.scroll(to: CGFloat(containerIndex / 2) * 600, animated: false)

                let startPoint = fixture.point(forGlyph: glyphRange.location + 2, containerIndex: containerIndex)
                let endPoint = fixture.point(forGlyph: glyphRange.location + 10, containerIndex: containerIndex)
                let target = try fixture.hitView(at: startPoint)
                XCTAssertTrue(target === fixture.textView)
                target.mouseDown(with: try fixture.event(.leftMouseDown, at: startPoint))
                XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: 0))
                target.mouseDragged(with: try fixture.event(.leftMouseDragged, at: endPoint))
                XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: end - start),
                               "container=\(containerIndex), width=\(width), dragging")
                target.mouseUp(with: try fixture.event(.leftMouseUp, at: endPoint))
                XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: end - start),
                               "container=\(containerIndex), width=\(width), released")
            }
        }
    }

    func testRightColumnContextMenuUsesClickedCharacterAndKeepsSelection() throws {
        let fixture = Fixture(columns: 2)
        defer { fixture.window.close() }
        let manager = try XCTUnwrap(fixture.textView.layoutManager)
        let speakAction = NSSelectorFromString("speakFromSelection")
        let highlightAction = NSSelectorFromString("highlightSelection")
        for index in [1, 3] {
            fixture.scrollView.scroll(to: CGFloat(index / 2) * 600, animated: false)
            let glyph = manager.glyphRange(for: manager.textContainers[index]).location + 2
            let location = manager.characterIndexForGlyph(at: glyph)
            let point = fixture.point(forGlyph: glyph, containerIndex: index)
            let event = try fixture.event(.rightMouseDown, at: point)
            let target = try fixture.hitView(at: point)
            XCTAssertTrue(target === fixture.textView)
            fixture.textView.setSelectedRange(NSRange(location: 0, length: 0))
            let menu = try XCTUnwrap(target.menu(for: event))
            let speakItem = try XCTUnwrap(menu.items.first { $0.action == speakAction })
            var spokenLocation: Int?
            fixture.textView.onSpeak = { spokenLocation = $0 }
            XCTAssertTrue(NSApp.sendAction(speakAction, to: speakItem.target, from: speakItem))
            XCTAssertEqual(spokenLocation, location)

            let selection = NSRange(location: location, length: 8)
            fixture.textView.setSelectedRange(selection)
            let selectionMenu = try XCTUnwrap(target.menu(for: event))
            XCTAssertNotNil(selectionMenu.items.first { $0.action == highlightAction })
            XCTAssertEqual(fixture.textView.selectedRange(), selection)
        }
    }

    func testHiddenAndClippedPageContentDoesNotReceiveMouseEvents() throws {
        let fixture = Fixture(columns: 2)
        defer { fixture.window.close() }
        let point = NSPoint(x: 500, y: 200)
        fixture.textView.isHidden = true
        XCTAssertFalse(try fixture.hitView(at: point) === fixture.textView)
        fixture.textView.isHidden = false
        fixture.scrollView.isHidden = true
        XCTAssertNil(fixture.textView.hitTest(fixture.textView.convert(point, to: fixture.textView.superview)))
        fixture.scrollView.isHidden = false
        let offscreenPoint = NSPoint(x: 500, y: 800)
        XCTAssertNil(fixture.textView.hitTest(fixture.textView.convert(offscreenPoint, to: fixture.textView.superview)))
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let scrollView: ReaderScrollView
        let textView: ReaderTextView
        let columns: Int

        init(columns: Int, width: CGFloat = 900) {
            _ = NSApplication.shared
            self.columns = columns
            let frame = NSRect(x: 0, y: 0, width: width, height: 600)
            scrollView = ReaderScrollView(frame: frame)
            textView = ReaderTextView(frame: frame)
            window = NSWindow(contentRect: scrollView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.contentView = scrollView
            scrollView.wantsLayer = true
            scrollView.layer?.masksToBounds = true
            scrollView.contentView.wantsLayer = true
            textView.wantsLayer = true
            scrollView.configure(flow: .paging(orientation: .horizontal, columns: columns == 1 ? .single : .double))
            textView.isEditable = false
            textView.isSelectable = true
            textView.selectedTextAttributes = [.foregroundColor: NSColor.white]
            textView.isHorizontallyResizable = false
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.documentView = textView
            textView.setReadingInsets(horizontal: 56, vertical: 64)
            textView.textStorage?.setAttributedString(NSAttributedString(
                string: String(repeating: "Text selection across page columns.\n", count: 180),
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)]
            ))
            textView.configurePageColumns(columns, viewportHeight: 600)
        }

        func point(forGlyph glyph: Int, containerIndex: Int) -> NSPoint {
            let manager = textView.layoutManager!
            let container = manager.textContainers[containerIndex]
            let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            return NSPoint(
                x: textView.textContainerInset.width + CGFloat(containerIndex % columns) * (container.size.width + 36) + rect.minX + 1,
                y: 64 + CGFloat(containerIndex / columns) * 600 + rect.midY
            )
        }

        func hitView(at point: NSPoint) throws -> NSView {
            try XCTUnwrap(scrollView.hitTest(textView.convert(point, to: scrollView.superview)))
        }

        func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: textView.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
            ))
        }
    }
}
