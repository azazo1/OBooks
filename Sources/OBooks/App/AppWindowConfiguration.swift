import AppKit
import SwiftUI

enum AppWindowConfiguration {
    /// 把窗口标成台前调度的主窗口, 聚焦时点击桌面才能被收入一侧.
    static func applyPrimaryStageBehavior(_ window: NSWindow) {
        window.level = .normal
        window.animationBehavior = .documentWindow

        var behavior = window.collectionBehavior
        behavior.subtract([
            .auxiliary,
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .transient,
            .stationary,
            .fullScreenAuxiliary,
            .fullScreenNone,
            .ignoresCycle,
            .fullScreenDisallowsTiling
        ])
        behavior.formUnion([
            .primary,
            .managed,
            .fullScreenPrimary,
            .fullScreenAllowsTiling,
            .participatesInCycle
        ])
        window.collectionBehavior = behavior
    }

    /// 按当前屏幕可见区域居中, 避免新窗口落在边角.
    static func centerOnScreen(_ window: NSWindow) {
        guard let screen = preferredScreen(for: window) else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.origin.x + ((visible.width - frame.width) / 2).rounded()
        frame.origin.y = visible.origin.y + ((visible.height - frame.height) / 2).rounded()
        window.setFrame(frame, display: true)
    }

    static func preferredScreen(for window: NSWindow) -> NSScreen? {
        NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// 给 SwiftUI 场景窗口补上台前调度主窗口标记.
struct PrimaryWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowHookView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowHookView)?.applyIfNeeded()
    }

    private final class WindowHookView: NSView {
        private var keyObservation: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyObservation {
                NotificationCenter.default.removeObserver(keyObservation)
                self.keyObservation = nil
            }
            applyIfNeeded()
            guard let window else { return }
            keyObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.applyIfNeeded()
            }
        }

        deinit {
            if let keyObservation {
                NotificationCenter.default.removeObserver(keyObservation)
            }
        }

        func applyIfNeeded() {
            guard let window else { return }
            AppWindowConfiguration.applyPrimaryStageBehavior(window)
        }
    }
}
