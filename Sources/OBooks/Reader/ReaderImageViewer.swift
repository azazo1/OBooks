import AppKit
import SwiftUI

struct ReaderImageViewer: View {
    let image: NSImage
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var magnificationStart: CGFloat?
    @State private var dragStart: CGSize?

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

            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayedSize.width, height: displayedSize.height)
                    .offset(offset)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
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
                                guard zoom > 1.001 else { return }
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
                                offset = clampedOffset(
                                    offset,
                                    displayedSize: displayedSize,
                                    contentSize: contentSize
                                )
                                dragStart = nil
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
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
                    HStack(spacing: 10) {
                        Text("图片预览")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                        Spacer()
                        Text("\(Int(zoom * 100))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.82))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.12), in: Circle())
                        .help("关闭图片预览")
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(.black.opacity(0.28))
                    Spacer()
                }
                .allowsHitTesting(true)

                ReaderImageViewerEventMonitor { delta in
                    let step = max(-0.65, min(0.65, delta * 0.012))
                    zoom = clampedZoom(zoom + step, fitScale: fitScale)
                    offset = clampedOffset(
                        offset,
                        displayedSize: CGSize(
                            width: baseSize.width * zoom,
                            height: baseSize.height * zoom
                        ),
                        contentSize: contentSize
                    )
                }
                .frame(width: 1, height: 1)
            }
            .onAppear {
                zoom = 1
                offset = .zero
            }
        }
        .onExitCommand(perform: onClose)
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
}

private struct ReaderImageViewerEventMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

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
        let onScroll: (CGFloat) -> Void
        var monitor: Any?

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
        }

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      event.window === NSApp.keyWindow else { return event }
                let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
                guard delta != 0 else { return event }
                onScroll(delta)
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
