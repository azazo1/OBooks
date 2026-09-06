import AppKit
import SwiftUI

/// 给 SwiftUI Settings 窗口打上身份并套用设置窗行为.
struct SettingsWindowProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Probe()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            AppWindowConfiguration.applySettingsWindowBehavior(window)
        }
    }

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            AppWindowConfiguration.applySettingsWindowBehavior(window)
        }
    }
}
