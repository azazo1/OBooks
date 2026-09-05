import AppKit
import OSLog
import SwiftUI

struct ReaderImageViewer: View {
    let image: NSImage
    let sourceRect: NSRect
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var presentationProgress: CGFloat = 0
    @State private var isClosing = false
    @State private var isTitleHovered = false

    private let logger = Logger(subsystem: "com.obooks.app", category: "reader.image-preview")

    var body: some View {
        GeometryReader { geometry in
            let metrics = ReaderImagePreviewMetrics(imageSize: image.size, canvasSize: geometry.size)
            let targetRect = metrics.imageRect(zoom: zoom, offset: offset)
            let localSourceRect = CGRect(
                x: sourceRect.minX,
                y: geometry.size.height - sourceRect.maxY,
                width: max(1, sourceRect.width),
                height: max(1, sourceRect.height)
            )
            let visibleRect = interpolatedRect(from: localSourceRect, to: targetRect, progress: presentationProgress)
            let isInteractive = presentationProgress > 0.99 && !isClosing

            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()
                    .opacity(0.94 * presentationProgress)
                    .allowsHitTesting(false)

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: visibleRect.width, height: visibleRect.height)
                    .position(x: visibleRect.midX, y: visibleRect.midY)
                    .opacity(max(0.05, presentationProgress))
                    .allowsHitTesting(false)

                ReaderImagePreviewClickCatcher(
                    imageRect: visibleRect,
                    isInteractive: isInteractive,
                    allowsPan: zoom > 1.001,
                    onClose: requestClose,
                    onToggleZoom: {
                        let next = metrics.toggledZoom(zoom)
                        withAnimation(.easeOut(duration: 0.18)) {
                            zoom = next
                            if next <= 1.01 { offset = .zero }
                        }
                        logger.info("图片预览双击缩放: \(next, format: .fixed(precision: 2))")
                    },
                    onPan: { delta in
                        offset = metrics.clampedOffset(
                            CGSize(width: offset.width + delta.width, height: offset.height + delta.height),
                            zoom: zoom
                        )
                    },
                    onPanEnd: {
                        withAnimation(.easeOut(duration: 0.16)) {
                            offset = metrics.clampedOffset(offset, zoom: zoom)
                        }
                    },
                    onMagnify: { magnification in
                        zoom = metrics.clampedZoom(zoom * (1 + magnification))
                        offset = metrics.clampedOffset(offset, zoom: zoom)
                    },
                    onScroll: { event in
                        let effect = ReaderImagePreviewMetrics.scrollEffect(
                            deltaX: event.scrollingDeltaX,
                            deltaY: event.scrollingDeltaY,
                            command: event.modifierFlags.contains(.command),
                            shift: event.modifierFlags.contains(.shift)
                        )
                        withAnimation(.easeOut(duration: 0.1)) {
                            if effect.zoomStep != 0 {
                                zoom = metrics.clampedZoom(zoom + effect.zoomStep)
                            }
                            if effect.pan != .zero {
                                offset = metrics.clampedOffset(
                                    CGSize(
                                        width: offset.width + effect.pan.width,
                                        height: offset.height + effect.pan.height
                                    ),
                                    zoom: zoom
                                )
                            }
                        }
                    },
                    onExport: { ReaderImageExporter.export(image) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .top) {
                header(visibleRect: visibleRect, canvasWidth: geometry.size.width)
                    .frame(width: geometry.size.width)
                    .opacity(presentationProgress)
            }
            .onAppear {
                zoom = 1
                offset = .zero
                presentationProgress = 0
                logger.info(
                    "打开图片预览: native=\(image.size.width, format: .fixed(precision: 0))x\(image.size.height, format: .fixed(precision: 0)), fit=\(metrics.fitScale, format: .fixed(precision: 2))"
                )
                withAnimation(.easeInOut(duration: 0.34)) {
                    presentationProgress = 1
                }
            }
        }
        .onExitCommand(perform: requestClose)
    }

    private func header(visibleRect: CGRect, canvasWidth: CGFloat) -> some View {
        ZStack {
            let titleCovered = visibleRect.minY < 52 && visibleRect.maxY > 0
                && visibleRect.minX < canvasWidth * 0.72 && visibleRect.maxX > canvasWidth * 0.28
            Text("图片预览")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background {
                    if !titleCovered || isTitleHovered {
                        Capsule().fill(.black.opacity(0.28))
                    }
                }
                .onHover { isTitleHovered = $0 }
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Spacer()
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                Button(action: requestClose) {
                    Group() {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 28, height: 28)
                    }
                    .contentShape(Rectangle())
                    .overlay {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 28, height: 28)
                            .allowsHitTesting(false)
                    }
                }
                .buttonStyle(.plain)
                .help("关闭图片预览")
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
    }

    private func interpolatedRect(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        let value = min(1, max(0, progress))
        return CGRect(
            x: from.minX + (to.minX - from.minX) * value,
            y: from.minY + (to.minY - from.minY) * value,
            width: from.width + (to.width - from.width) * value,
            height: from.height + (to.height - from.height) * value
        )
    }

    private func requestClose() {
        guard !isClosing else { return }
        isClosing = true
        logger.info("关闭图片预览")
        withAnimation(.easeInOut(duration: 0.3)) {
            presentationProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            onClose()
        }
    }
}

private struct ReaderImagePreviewClickCatcher: NSViewRepresentable {
    var imageRect: CGRect
    var isInteractive: Bool
    var allowsPan: Bool
    var onClose: () -> Void
    var onToggleZoom: () -> Void
    var onPan: (CGSize) -> Void
    var onPanEnd: () -> Void
    var onMagnify: (CGFloat) -> Void
    var onScroll: (NSEvent) -> Void
    var onExport: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.imageRect = imageRect
        nsView.isInteractive = isInteractive
        nsView.allowsPan = allowsPan
        nsView.onClose = onClose
        nsView.onToggleZoom = onToggleZoom
        nsView.onPan = onPan
        nsView.onPanEnd = onPanEnd
        nsView.onMagnify = onMagnify
        nsView.onScroll = onScroll
        nsView.onExport = onExport
    }

    final class ClickView: NSView {
        var imageRect: CGRect = .zero
        var isInteractive = false
        var allowsPan = false
        var onClose: (() -> Void)?
        var onToggleZoom: (() -> Void)?
        var onPan: ((CGSize) -> Void)?
        var onPanEnd: (() -> Void)?
        var onMagnify: ((CGFloat) -> Void)?
        var onScroll: ((NSEvent) -> Void)?
        var onExport: (() -> Void)?

        private var dragOrigin: NSPoint?
        private var lastDragPoint: NSPoint?
        private var startedOnImage = false
        private var isPanning = false
        private var didPress = false
        private var scrollMonitor: Any?

        override var isOpaque: Bool { false }
        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeScrollMonitor()
            guard window != nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      event.window === self.window,
                      self.window === NSApp.keyWindow,
                      self.window?.attachedSheet == nil,
                      self.isInteractive else { return event }
                guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return event }
                self.onScroll?(event)
                return nil
            }
        }

        deinit {
            removeScrollMonitor()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            guard isInteractive else { return }
            let point = convert(event.locationInWindow, from: nil)
            dragOrigin = point
            lastDragPoint = point
            startedOnImage = imageRect.contains(point)
            isPanning = false
            didPress = true
            if event.clickCount == 2, startedOnImage {
                onToggleZoom?()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard isInteractive, startedOnImage, allowsPan, let origin = dragOrigin else { return }
            let point = convert(event.locationInWindow, from: nil)
            if !isPanning {
                guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
                isPanning = true
            }
            if let last = lastDragPoint {
                onPan?(CGSize(width: point.x - last.x, height: point.y - last.y))
            }
            lastDragPoint = point
        }

        override func mouseUp(with event: NSEvent) {
            let pressed = didPress
            let panning = isPanning
            let pressedOnImage = startedOnImage
            dragOrigin = nil
            lastDragPoint = nil
            isPanning = false
            didPress = false
            startedOnImage = false
            guard isInteractive, pressed else { return }
            let point = convert(event.locationInWindow, from: nil)
            if panning {
                onPanEnd?()
                return
            }
            if event.clickCount == 1, !pressedOnImage, !imageRect.contains(point) {
                onClose?()
            }
        }

        override func magnify(with event: NSEvent) {
            guard isInteractive else { return }
            onMagnify?(event.magnification)
        }

        override func scrollWheel(with event: NSEvent) {
            guard isInteractive else { return }
            onScroll?(event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let point = convert(event.locationInWindow, from: nil)
            guard imageRect.contains(point) else { return nil }
            let menu = NSMenu(title: "图片")
            menu.autoenablesItems = false
            let item = NSMenuItem(title: "导出图片...", action: #selector(exportImage), keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            menu.addItem(item)
            return menu
        }

        @objc private func exportImage() {
            onExport?()
        }

        private func removeScrollMonitor() {
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
            }
            scrollMonitor = nil
        }
    }
}
