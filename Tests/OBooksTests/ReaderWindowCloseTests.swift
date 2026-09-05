import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderWindowCloseTests: XCTestCase {
    func testCloseCommandWorksWhenReaderChromeIsTransparent() throws {
        let window = makeWindow()
        let delegate = CloseDelegate()
        window.delegate = delegate
        defer {
            window.delegate = nil
            window.close()
        }
        let button = try XCTUnwrap(window.standardWindowButton(.closeButton))
        button.alphaValue = 0
        let item = NSMenuItem(title: "", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        XCTAssertTrue(window.validateMenuItem(item))
        XCTAssertEqual(button.alphaValue, 0)
        window.performClose(item)

        XCTAssertTrue(delegate.didCheckClose)
        XCTAssertTrue(delegate.didClose)
    }

    func testCloseCommandRespectsDelegateVetoAndRestoresButtonTransparency() throws {
        let window = makeWindow()
        let delegate = CloseDelegate()
        delegate.allowsClose = false
        window.delegate = delegate
        defer {
            window.delegate = nil
            window.close()
        }
        let button = try XCTUnwrap(window.standardWindowButton(.closeButton))
        button.alphaValue = 0

        window.performClose(nil)

        XCTAssertTrue(delegate.didCheckClose)
        XCTAssertFalse(delegate.didClose)
        XCTAssertEqual(button.alphaValue, 0)
    }

    private func makeWindow() -> ReaderWindow {
        _ = NSApplication.shared
        let window = ReaderWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private final class CloseDelegate: NSObject, NSWindowDelegate {
        var allowsClose = true
        var didCheckClose = false
        var didClose = false

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            didCheckClose = true
            return allowsClose
        }

        func windowWillClose(_ notification: Notification) {
            didClose = true
        }
    }
}
