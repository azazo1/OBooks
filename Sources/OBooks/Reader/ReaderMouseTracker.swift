import AppKit
import SwiftUI

struct ReaderMouseTracker: NSViewRepresentable {
    let onMove: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = onMove
    }

    final class TrackingView: NSView {
        var onMove: (() -> Void)?

        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?()
        }
    }
}
