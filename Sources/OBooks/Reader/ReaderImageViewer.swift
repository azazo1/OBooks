import AppKit
import SwiftUI

struct ReaderImageViewer: View {
    let image: NSImage
    let sourceRect: NSRect
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var magnificationStart: CGFloat?
    @State private var dragStart: CGSize?
    @State private var presentationProgress: CGFloat = 0
    @State private var isClosing = false
    @State private var isTitleHovered = false

    var body: some View {
        GeometryReader { geometry in
            let contentSize = CGSize(
                width: max(1, geometry.size.width - 44),
                height: max(1, geometry.size.height - 104)
            )
            let fitScale = fitScale(for: contentSize)
            let baseSize = CGSize(
                width: max(1, image.size.width) * fitScale,
                height: max(1, image.size.height) * fitScale
            )
            let displayedSize = CGSize(
                width: baseSize.width * zoom,
                height: baseSize.height * zoom
            )
            let targetRect = CGRect(
                x: (geometry.size.width - displayedSize.width) / 2 + offset.width,
                y: (geometry.size.height - displayedSize.height) / 2 + offset.height,
                width: displayedSize.width,
                height: displayedSize.height
            )
            let localSourceRect = CGRect(
                x: sourceRect.minX,
                y: geometry.size.height - sourceRect.maxY,
                width: max(1, sourceRect.width),
                height: max(1, sourceRect.height)
            )
            let visibleRect = interpolatedRect(from: localSourceRect, to: targetRect, progress: presentationProgress)

            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .opacity(0.94 * presentationProgress)
                    .onTapGesture(perform: requestClose)

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: visibleRect.width, height: visibleRect.height)
                    .position(x: visibleRect.midX, y: visibleRect.midY)
                    .opacity(max(0.05, presentationProgress))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard presentationProgress > 0.99, !isClosing else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            if zoom > 1.01 {
                                zoom = 1
                                offset = .zero
                            } else {
                                zoom = oneToOneZoom(fitScale: fitScale)
                            }
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard presentationProgress > 0.99, zoom > 1.001, !isClosing else { return }
                                if dragStart == nil {
                                    dragStart = offset
                                }
                                offset = clampedOffset(
                                    CGSize(
                                        width: value.translation.width + (dragStart?.width ?? 0),
                                        height: value.translation.height + (dragStart?.height ?? 0)
                                    ),
                                    displayedSize: displayedSize,
                                    contentSize: contentSize
                                )
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.16)) {
                                    offset = clampedOffset(
                                        offset,
                                        displayedSize: displayedSize,
                                        contentSize: contentSize
                                    )
                                }
                                dragStart = nil
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard presentationProgress > 0.99, !isClosing else { return }
                                if magnificationStart == nil {
                                    magnificationStart = zoom
                                }
                                let start = magnificationStart ?? zoom
                                zoom = clampedZoom(start * value, fitScale: fitScale)
                                offset = clampedOffset(
                                    offset,
                                    displayedSize: CGSize(
                                        width: baseSize.width * zoom,
                                        height: baseSize.height * zoom
                                    ),
                                    contentSize: contentSize
                                )
                            }
                            .onEnded { _ in
                                magnificationStart = nil
                            }
                    )

                VStack(spacing: 0) {
                    ZStack {
                        let titleCovered = visibleRect.minY < 52 && visibleRect.maxY > 0 && visibleRect.minX < geometry.size.width * 0.72 && visibleRect.maxX > geometry.size.width * 0.28
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
                        HStack(spacing: 10) {
                            Spacer()
                            Text("\(Int(zoom * 100))%")
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
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    Spacer()
                }
                .opacity(presentationProgress)
                .allowsHitTesting(true)

                ReaderImageViewerEventMonitor { event in
                    guard presentationProgress > 0.99, !isClosing else { return }
                    let x = event.scrollingDeltaX
                    let y = event.scrollingDeltaY
                    let isZooming = event.modifierFlags.contains(.command)
                    let isShifted = event.modifierFlags.contains(.shift)

                    withAnimation(.easeOut(duration: 0.1)) {
                        if isZooming {
                            let delta = y != 0 ? y : x
                            let step = max(-0.65, min(0.65, delta * 0.012))
                            zoom = clampedZoom(zoom + step, fitScale: fitScale)
                        } else {
                            let horizontalDelta: CGFloat
                            if abs(x) > 0.01 {
                                horizontalDelta = x
                            } else if isShifted {
                                horizontalDelta = y
                            } else {
                                horizontalDelta = 0
                            }

                            let verticalDelta = isShifted ? 0 : y

                            offset = clampedOffset(
                                CGSize(
                                    width: offset.width + horizontalDelta,
                                    height: offset.height + verticalDelta
                                ),
                                displayedSize: CGSize(
                                    width: baseSize.width * zoom,
                                    height: baseSize.height * zoom
                                ),
                                contentSize: contentSize
                            )
                        }
                    }
                }
                .frame(width: 1, height: 1)
            }
            .onAppear {
                zoom = 1
                offset = .zero
                presentationProgress = 0
                withAnimation(.easeInOut(duration: 0.34)) {
                    presentationProgress = 1
                }
            }
        }
        .onExitCommand(perform: requestClose)
    }

    private func fitScale(for contentSize: CGSize) -> CGFloat {
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        return min(1, min(contentSize.width / width, contentSize.height / height))
    }

    private func oneToOneZoom(fitScale: CGFloat) -> CGFloat {
        max(1, 1 / max(fitScale, 0.001))
    }

    private func clampedZoom(_ value: CGFloat, fitScale: CGFloat) -> CGFloat {
        max(1, min(max(8, oneToOneZoom(fitScale: fitScale)), value))
    }

    private func clampedOffset(_ value: CGSize, displayedSize: CGSize, contentSize: CGSize) -> CGSize {
        let horizontalLimit = max(0, (displayedSize.width - contentSize.width) / 2)
        let verticalLimit = max(0, (displayedSize.height - contentSize.height) / 2)
        return CGSize(
            width: min(horizontalLimit, max(-horizontalLimit, value.width)),
            height: min(verticalLimit, max(-verticalLimit, value.height))
        )
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
        withAnimation(.easeInOut(duration: 0.3)) {
            presentationProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            onClose()
        }
    }
}

private struct ReaderImageViewerEventMonitor: NSViewRepresentable {
    let onScroll: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        let onScroll: (NSEvent) -> Void
        var monitor: Any?

        init(onScroll: @escaping (NSEvent) -> Void) {
            self.onScroll = onScroll
        }

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      event.window === NSApp.keyWindow else { return event }
                guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return event }
                onScroll(event)
                return nil
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
