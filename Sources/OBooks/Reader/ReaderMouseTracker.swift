import AppKit
import SwiftUI

struct ReaderMouseTracker: NSViewRepresentable {
    let chromeVisible: Bool
    let edgeThreshold: CGFloat
    let onProximityChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.chromeVisible = chromeVisible
        view.edgeThreshold = edgeThreshold
        view.onProximityChange = onProximityChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.chromeVisible = chromeVisible
        nsView.edgeThreshold = edgeThreshold
        nsView.onProximityChange = onProximityChange
        nsView.applyChromeVisibility()
    }

    final class TrackingView: NSView {
        var chromeVisible = true
        var edgeThreshold: CGFloat = 84
        var onProximityChange: ((Bool) -> Void)?
        private var eventMonitor: Any?
        private var lastValue: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeTracking()
            guard let window else { return }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(fullScreenDidChange(_:)), name: name, object: window
                )
            }
            applyChromeVisibility()
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        deinit {
            removeTracking()
        }

        func applyChromeVisibility(animated: Bool = true) {
            guard let window else { return }
            let isFullScreen = window.styleMask.contains(.fullScreen)
            // 全屏标题栏由 macOS 显隐, 阅读工具栏不能把其中的窗口按钮变透明.
            let buttonsVisible = isFullScreen || chromeVisible
            let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated && !isFullScreen ? 0.18 : 0
                for type in buttonTypes {
                    guard let button = window.standardWindowButton(type) else { continue }
                    button.animator().alphaValue = buttonsVisible ? 1 : 0
                }
            }
        }

        @objc private func fullScreenDidChange(_ notification: Notification) {
            applyChromeVisibility(animated: false)
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window else {
                report(false)
                return
            }
            let location = convert(event.locationInWindow, from: nil)
            let verticalDistance = min(abs(location.y - bounds.minY), abs(bounds.maxY - location.y))
            report(bounds.contains(location) && verticalDistance <= edgeThreshold)
        }

        private func report(_ value: Bool) {
            guard lastValue != value else { return }
            lastValue = value
            onProximityChange?(value)
        }

        private func removeTracking() {
            NotificationCenter.default.removeObserver(self)
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }
    }
}
