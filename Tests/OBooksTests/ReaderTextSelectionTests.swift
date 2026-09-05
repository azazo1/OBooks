import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderTextSelectionTests: XCTestCase {
    func testClickingBlankSpaceClearsDoubleColumnSelection() throws {
        let fixture = Fixture(columns: 2)
        defer { fixture.window.close() }
        fixture.textView.setSelectedRange(NSRange(location: 2, length: 12))

        let blankPoint = NSPoint(x: 560, y: 120)
        fixture.textView.mouseDown(with: try fixture.event(.leftMouseDown, at: blankPoint))

        XCTAssertEqual(fixture.textView.selectedRange().length, 0)
    }

    func testMouseDragSelectsTextInEachPageColumn() throws {
        for columns in [2] {
            let fixture = Fixture(columns: columns)
            defer { fixture.window.close() }
            let manager = try XCTUnwrap(fixture.textView.layoutManager)
            for containerIndex in 0...columns {
                let container = manager.textContainers[containerIndex]
                let glyphRange = manager.glyphRange(for: container)
                let start = manager.characterIndexForGlyph(at: glyphRange.location + 2)
                let end = manager.characterIndexForGlyph(at: glyphRange.location + 10)
                fixture.scrollView.scroll(to: CGFloat(containerIndex / columns) * 600, animated: false)

                let startPoint = fixture.point(forGlyph: glyphRange.location + 2, containerIndex: containerIndex)
                let endPoint = fixture.point(forGlyph: glyphRange.location + 10, containerIndex: containerIndex)
                fixture.textView.mouseDown(with: try fixture.event(.leftMouseDown, at: startPoint))
                XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: 0))
                fixture.textView.mouseDragged(with: try fixture.event(.leftMouseDragged, at: endPoint))
                XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: end - start),
                               "columns=\(columns), container=\(containerIndex), dragging")
                fixture.textView.mouseUp(with: try fixture.event(.leftMouseUp, at: endPoint))
                XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: end - start),
                               "columns=\(columns), container=\(containerIndex), released")
            }
        }
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let scrollView = ReaderScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let textView = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let columns: Int

        init(columns: Int) {
            _ = NSApplication.shared
            self.columns = columns
            window = NSWindow(contentRect: scrollView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scrollView
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
                x: 56 + CGFloat(containerIndex % columns) * (container.size.width + 36) + rect.minX + 1,
                y: 64 + CGFloat(containerIndex / columns) * 600 + rect.midY
            )
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
