import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderWindowChromeTests: XCTestCase {
    func testFullScreenKeepsButtonsVisibleAfterReaderChromeHides() async throws {
        let window = makeWindow()
        defer { window.close() }
        let tracker = ReaderMouseTracker.TrackingView()
        tracker.chromeVisible = false
        window.contentView = tracker
        tracker.applyChromeVisibility(animated: false)
        try assertButtons(in: window, haveAlpha: 0)

        window.simulatesFullScreen = true
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        try assertButtons(in: window, haveAlpha: 1)

        tracker.chromeVisible = true
        tracker.applyChromeVisibility()
        tracker.chromeVisible = false
        tracker.applyChromeVisibility()
        try await Task.sleep(for: .milliseconds(250))
        try assertButtons(in: window, haveAlpha: 1)

        window.simulatesFullScreen = false
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        try assertButtons(in: window, haveAlpha: 0)

        tracker.chromeVisible = true
        tracker.applyChromeVisibility(animated: false)
        try assertButtons(in: window, haveAlpha: 1)
    }

    func testAttachingTrackerToFullScreenWindowRestoresTransparentButtons() throws {
        let window = makeWindow()
        defer { window.close() }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            try XCTUnwrap(window.standardWindowButton(type)).alphaValue = 0
        }
        window.simulatesFullScreen = true

        let tracker = ReaderMouseTracker.TrackingView()
        tracker.chromeVisible = false
        window.contentView = tracker

        try assertButtons(in: window, haveAlpha: 1)
    }

    private func makeWindow() -> TestWindow {
        _ = NSApplication.shared
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func assertButtons(
        in window: NSWindow, haveAlpha alpha: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try XCTUnwrap(window.standardWindowButton(type), file: file, line: line)
            XCTAssertEqual(button.alphaValue, alpha, accuracy: 0.001, file: file, line: line)
        }
    }

    private final class TestWindow: NSWindow {
        var simulatesFullScreen = false

        override var styleMask: NSWindow.StyleMask {
            get { simulatesFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
            set { super.styleMask = newValue }
        }
    }
}
