import AppKit
import SwiftUI

/// 向系统声明当前区域为默认箭头光标, 阻断下层正文的 I-beam 穿透.
struct SystemCursorBarrier: NSViewRepresentable {
    func makeNSView(context: Context) -> BarrierView { BarrierView() }
    func updateNSView(_ nsView: BarrierView, context: Context) {}

    final class BarrierView: NSView {
        private var trackingArea: NSTrackingArea?

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            super.updateTrackingAreas()
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        override func mouseMoved(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.arrow.set()
        }
    }
}
