import AppKit
import QuartzCore

@MainActor
final class ReaderScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    var pageTurn: ((Int) -> Void)?
    var pageFlow: ReaderFlowMode = .scrolling(scope: .chapter)
    private var scrollTargetY: CGFloat?
    private var refreshLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var pageTurnInFlight = false
    private let responseDuration: CFTimeInterval = 0.12

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopSmoothScroll()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        if pageFlow.isPaging {
            handlePageScroll(with: event)
            return
        }
        guard !handleScrollWheel(with: event) else { return }
        super.scrollWheel(with: event)
    }

    func notifyUserScroll() {
        onUserScroll?()
    }

    func configure(flow: ReaderFlowMode) {
        pageFlow = flow
    }

    func animatePageTransition(
        orientation: ReaderPageOrientation,
        direction: Int,
        change: () -> Void
    ) {
        guard let before = snapshotImage() else {
            change()
            return
        }
        change()
        displayIfNeeded()
        contentView.displayIfNeeded()
        documentView?.displayIfNeeded()
        guard let after = snapshotImage() else { return }

        let oldView = transitionImageView(image: before)
        let newView = transitionImageView(image: after)
        let restingFrame = bounds
        oldView.frame = restingFrame
        newView.frame = incomingFrame(
            from: restingFrame,
            orientation: orientation,
            direction: direction
        )
        newView.layer?.shadowColor = NSColor.black.cgColor
        newView.layer?.shadowOpacity = 0.3
        newView.layer?.shadowRadius = 15
        newView.layer?.shadowOffset = shadowOffset(
            orientation: orientation,
            direction: direction
        )
        addSubview(oldView)
        addSubview(newView)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            oldView.animator().frame = outgoingFrame(
                from: restingFrame,
                orientation: orientation,
                direction: direction
            )
            oldView.animator().alphaValue = 0.56
            newView.animator().frame = restingFrame
        } completionHandler: { [weak oldView, weak newView] in
            oldView?.removeFromSuperview()
            newView?.removeFromSuperview()
        }
    }

    @discardableResult
    func handlePageScroll(with event: NSEvent) -> Bool {
        guard pageFlow.isPaging else { return false }
        let delta: CGFloat
        switch pageFlow.pageOrientation {
        case .horizontal:
            delta = event.scrollingDeltaX != 0 ? CGFloat(event.scrollingDeltaX) : CGFloat(event.scrollingDeltaY)
        case .vertical, .none:
            delta = CGFloat(event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX)
        }
        guard abs(delta) > 0.01, !pageTurnInFlight else { return true }
        pageTurnInFlight = true
        pageTurn?(delta > 0 ? -1 : 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pageTurnInFlight = false
        }
        return true
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

    private func snapshotImage() -> NSImage? {
        guard bounds.width > 1, bounds.height > 1,
              let representation = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func transitionImageView(image: NSImage) -> NSImageView {
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        return imageView
    }

    private func incomingFrame(
        from frame: NSRect,
        orientation: ReaderPageOrientation,
        direction: Int
    ) -> NSRect {
        var result = frame
        switch orientation {
        case .horizontal:
            result.origin.x += frame.width * CGFloat(direction)
        case .vertical:
            result.origin.y -= frame.height * CGFloat(direction)
        }
        return result
    }

    private func outgoingFrame(
        from frame: NSRect,
        orientation: ReaderPageOrientation,
        direction: Int
    ) -> NSRect {
        var result = frame.insetBy(dx: frame.width * 0.008, dy: frame.height * 0.008)
        switch orientation {
        case .horizontal:
            result.origin.x -= frame.width * 0.1 * CGFloat(direction)
        case .vertical:
            result.origin.y += frame.height * 0.1 * CGFloat(direction)
        }
        return result
    }

    private func shadowOffset(
        orientation: ReaderPageOrientation,
        direction: Int
    ) -> CGSize {
        switch orientation {
        case .horizontal:
            return CGSize(width: -10 * direction, height: 0)
        case .vertical:
            return CGSize(width: 0, height: 10 * direction)
        }
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
