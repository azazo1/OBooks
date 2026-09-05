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
        for columns in [1, 2] {
            for width: CGFloat in [900, 1180] {
                let fixture = Fixture(columns: columns, width: width)
                defer { fixture.window.close() }
                let manager = try XCTUnwrap(fixture.textView.layoutManager)
                for containerIndex in 0..<(columns * 2) {
                    let container = manager.textContainers[containerIndex]
                    let glyphRange = manager.glyphRange(for: container)
                    let start = manager.characterIndexForGlyph(at: glyphRange.location + 2)
                    let end = manager.characterIndexForGlyph(at: glyphRange.location + 10)
                    fixture.scrollView.scroll(to: CGFloat(containerIndex / columns) * 600, animated: false)

                    let startPoint = fixture.point(forGlyph: glyphRange.location + 2, containerIndex: containerIndex)
                    let endPoint = fixture.point(forGlyph: glyphRange.location + 10, containerIndex: containerIndex)
                    for (anchorPoint, draggedPoint, anchor) in [
                        (startPoint, endPoint, start),
                        (endPoint, startPoint, end)
                    ] {
                        let target = try fixture.hitView(at: anchorPoint)
                        XCTAssertTrue(target === fixture.textView)
                        target.mouseDown(with: try fixture.event(.leftMouseDown, at: anchorPoint))
                        XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: anchor, length: 0))
                        target.mouseDragged(with: try fixture.event(.leftMouseDragged, at: draggedPoint))
                        XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: end - start),
                                       "columns=\(columns), container=\(containerIndex), width=\(width), anchor=\(anchor), dragging")
                        target.mouseUp(with: try fixture.event(.leftMouseUp, at: draggedPoint))
                        XCTAssertEqual(fixture.textView.selectedRange(), NSRange(location: start, length: end - start),
                                       "columns=\(columns), container=\(containerIndex), width=\(width), anchor=\(anchor), released")
                    }
                }
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

    func testImageContextMenuUsesClickedImageAcrossReadingModes() throws {
        let content = NSMutableAttributedString(string: "")
        var images: [Int: NSImage] = [:]
        for _ in 0..<18 {
            content.append(NSAttributedString(string: "Caption\n", attributes: [.font: NSFont.systemFont(ofSize: 18)]))
            let image = NSImage(size: NSSize(width: 160, height: 120))
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: image.size)
            images[content.length] = image
            content.append(NSAttributedString(attachment: attachment))
            content.append(NSAttributedString(string: "\n"))
        }
        let exportAction = NSSelectorFromString("exportImage:")
        for columns in [0, 1, 2] {
            let fixture = Fixture(columns: max(1, columns), content: content)
            defer { fixture.window.close() }
            if columns == 0 {
                fixture.scrollView.configure(flow: .scrolling(scope: .chapter))
                fixture.textView.configurePageColumns(0, viewportHeight: 600)
                fixture.textView.updateDocumentHeight(minimumHeight: 600)
            }
            let manager = try XCTUnwrap(fixture.textView.layoutManager)
            let containerCount = columns == 0 ? 1 : columns * 2
            XCTAssertGreaterThanOrEqual(manager.textContainers.count, containerCount)
            let selection = NSRange(location: 0, length: 3)
            fixture.textView.setSelectedRange(selection)
            for index in 0..<containerCount {
                let container = manager.textContainers[index]
                let range = manager.characterRange(forGlyphRange: manager.glyphRange(for: container), actualGlyphRange: nil)
                let location = try XCTUnwrap(images.keys.sorted().first { NSLocationInRange($0, range) })
                let glyph = manager.glyphIndexForCharacter(at: location)
                fixture.scrollView.scroll(to: CGFloat(index / max(1, columns)) * 600, animated: false)
                let point = fixture.point(forGlyph: glyph, containerIndex: index)
                let menu = try XCTUnwrap(fixture.textView.menu(for: fixture.event(.rightMouseDown, at: point)))
                let item = try XCTUnwrap(menu.items.first { $0.action == exportAction })
                XCTAssertTrue(item.target === fixture.textView)
                XCTAssertTrue(item.representedObject as? NSImage === images[location])
                XCTAssertEqual(fixture.textView.selectedRange(), selection)

                let blankPoint = NSPoint(x: fixture.textView.bounds.width - 10, y: point.y)
                let blankMenu = try XCTUnwrap(fixture.textView.menu(for: fixture.event(.rightMouseDown, at: blankPoint)))
                XCTAssertFalse(blankMenu.items.contains { $0.action == exportAction })
            }
            fixture.scrollView.scroll(to: 0, animated: false)
            let textPoint = fixture.point(forGlyph: 0, containerIndex: 0)
            let textMenu = try XCTUnwrap(fixture.textView.menu(for: fixture.event(.rightMouseDown, at: textPoint)))
            XCTAssertFalse(textMenu.items.contains { $0.action == exportAction })
        }
    }

    func testImagePreviewOpensOnClickEvenAfterSmallDrag() throws {
        let image = NSImage(size: NSSize(width: 160, height: 120))
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(origin: .zero, size: image.size)
        let content = NSMutableAttributedString(
            string: "Caption\n",
            attributes: [.font: NSFont.systemFont(ofSize: 18)]
        )
        let imageLocation = content.length
        content.append(NSAttributedString(attachment: attachment))
        content.append(NSAttributedString(string: "\nMore text after the image.\n"))

        for columns in [0, 1, 2] {
            let fixture = Fixture(columns: max(1, columns), content: content)
            defer { fixture.window.close() }
            if columns == 0 {
                fixture.scrollView.configure(flow: .scrolling(scope: .chapter))
                fixture.textView.configurePageColumns(0, viewportHeight: 600)
                fixture.textView.updateDocumentHeight(minimumHeight: 600)
            }
            let manager = try XCTUnwrap(fixture.textView.layoutManager)
            let glyph = manager.glyphIndexForCharacter(at: imageLocation)
            let point = fixture.point(forGlyph: glyph, containerIndex: 0)
            let dragged = NSPoint(x: point.x + 3, y: point.y + 2)
            let outside = NSPoint(x: fixture.textView.bounds.width - 10, y: point.y)
            var opened: NSImage?
            fixture.textView.onImageClick = { clicked, _ in opened = clicked }

            let target = try fixture.hitView(at: point)
            target.mouseDown(with: try fixture.event(.leftMouseDown, at: point))
            XCTAssertNil(opened)
            target.mouseDragged(with: try fixture.event(.leftMouseDragged, at: dragged))
            target.mouseUp(with: try fixture.event(.leftMouseUp, at: dragged))
            XCTAssertTrue(opened === image, "columns=\(columns)")

            opened = nil
            target.mouseDown(with: try fixture.event(.leftMouseDown, at: point))
            target.mouseDragged(with: try fixture.event(.leftMouseDragged, at: outside))
            target.mouseUp(with: try fixture.event(.leftMouseUp, at: outside))
            XCTAssertNil(opened, "columns=\(columns)")
        }
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let scrollView: ReaderScrollView
        let textView: ReaderTextView
        let columns: Int

        init(columns: Int, width: CGFloat = 900, content: NSAttributedString? = nil) {
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
            textView.textStorage?.setAttributedString(content ?? NSAttributedString(
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
