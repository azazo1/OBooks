import AppKit

final class ReaderWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: (NSWindow) -> Void
    private let onReadingActiveChange: (Bool) -> Void
    private var didCenterOnOpen = false

    init(
        onClose: @escaping (NSWindow) -> Void,
        onReadingActiveChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onClose = onClose
        self.onReadingActiveChange = onReadingActiveChange
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        AppWindowConfiguration.applyPrimaryStageBehavior(window)
        centerIfNeeded(window)
        onReadingActiveChange(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        onReadingActiveChange(false)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        onReadingActiveChange(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isKeyWindow else { return }
        onReadingActiveChange(true)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        centerIfNeeded(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let close = onClose
        DispatchQueue.main.async {
            close(window)
        }
    }

    private func centerIfNeeded(_ window: NSWindow) {
        guard !didCenterOnOpen else { return }
        guard window.frame.width >= 200, window.frame.height >= 200 else { return }
        didCenterOnOpen = true
        AppWindowConfiguration.centerOnScreen(window)
    }
}
