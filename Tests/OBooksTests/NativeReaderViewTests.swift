import AppKit
import XCTest
@testable import OBooks

@MainActor
final class NativeReaderViewTests: XCTestCase {
    func testTextViewExpandsForScrollableContent() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let textView = ReaderTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        let paragraph = String(repeating: "Native TextKit reading line.\n", count: 120)
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: paragraph,
            attributes: [.font: NSFont.systemFont(ofSize: 18)]
        ))
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }

        XCTAssertGreaterThan(textView.frame.height, scrollView.contentSize.height)
        XCTAssertGreaterThan(textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0, scrollView.contentSize.height)
    }
}
