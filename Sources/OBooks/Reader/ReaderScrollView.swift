import AppKit
import QuartzCore

@MainActor
final class ReaderScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    private var scrollTargetY: CGFloat?
    private var refreshLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private let responseDuration: CFTimeInterval = 0.12

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopSmoothScroll()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        guard !handleScrollWheel(with: event) else { return }
        super.scrollWheel(with: event)
    }

    func notifyUserScroll() {
        onUserScroll?()
    }

    @discardableResult
    func handleScrollWheel(with event: NSEvent) -> Bool {
        guard !event.hasPreciseScrollingDeltas,
              event.scrollingDeltaY != 0,
              let documentView else {
            stopSmoothScroll()
            return false
        }

        let maximum = max(0, documentView.frame.height - contentView.bounds.height)
        let currentTarget = scrollTargetY ?? contentView.bounds.origin.y
        let delta = CGFloat(event.scrollingDeltaY) * 36
        scrollTargetY = min(max(currentTarget - delta, 0), maximum)
        startDisplayLink()
        return true
    }

    func scroll(to offset: CGFloat, animated: Bool) {
        let maximum = max(0, (documentView?.frame.height ?? 0) - contentView.bounds.height)
        let target = min(max(offset, 0), maximum)
        guard animated else {
            stopSmoothScroll()
            setScrollOffset(target)
            return
        }
        scrollTargetY = target
        startDisplayLink()
    }

    func prepareForProgrammaticScroll() {
        stopSmoothScroll()
    }

    private func startDisplayLink() {
        guard refreshLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        refreshLink = link
        lastFrameTimestamp = nil
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        updateSmoothScroll(link)
    }

    private func updateSmoothScroll(_ link: CADisplayLink) {
        guard let target = scrollTargetY else {
            stopSmoothScroll()
            return
        }

        let current = contentView.bounds.origin.y
        let distance = target - current
        guard abs(distance) >= 0.5 else {
            setScrollOffset(target)
            stopSmoothScroll()
            return
        }

        let frameDuration: CFTimeInterval
        if let lastFrameTimestamp {
            frameDuration = min(max(link.timestamp - lastFrameTimestamp, 1.0 / 240.0), 1.0 / 30.0)
        } else {
            frameDuration = max(link.duration, 1.0 / 120.0)
        }
        lastFrameTimestamp = link.timestamp
        let blend = 1 - pow(0.01, frameDuration / responseDuration)
        setScrollOffset(current + distance * blend)
    }

    private func setScrollOffset(_ y: CGFloat) {
        contentView.scroll(to: NSPoint(x: contentView.bounds.origin.x, y: y))
        reflectScrolledClipView(contentView)
    }

    private func stopSmoothScroll() {
        refreshLink?.invalidate()
        refreshLink = nil
        scrollTargetY = nil
        lastFrameTimestamp = nil
    }
}
