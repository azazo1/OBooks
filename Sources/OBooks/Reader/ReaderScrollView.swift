import AppKit
import QuartzCore

@MainActor
final class ReaderScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    var pageTurn: ((Int, Bool) -> Bool)?
    var pageTurnRollbackOffset: CGFloat?
    var pageFlow: ReaderFlowMode = .scrolling(scope: .chapter)
    private var scrollTargetY: CGFloat?
    private var refreshLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var pageTurnInFlight = false
    private var interactivePage: InteractivePageTransition?
    private var interactivePageSettling = false
    private var preciseGestureActive = false
    private var precisePageAttempted = false
    private var documentHiddenBeforeTransition: Bool?
    private let responseDuration: CFTimeInterval = 0.12

    private final class InteractivePageTransition: @unchecked Sendable {
        let oldView: NSImageView
        let newView: NSImageView
        let restingFrame: NSRect
        let startOffset: CGFloat
        let direction: Int
        let orientation: ReaderPageOrientation
        var translation: CGFloat = 0

        init(
            oldView: NSImageView,
            newView: NSImageView,
            restingFrame: NSRect,
            startOffset: CGFloat,
            direction: Int,
            orientation: ReaderPageOrientation
        ) {
            self.oldView = oldView
            self.newView = newView
            self.restingFrame = restingFrame
            self.startOffset = startOffset
            self.direction = direction
            self.orientation = orientation
        }
    }

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
        beginTransitionIsolation()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = transitionTimingFunction()
            oldView.animator().frame = outgoingFrame(
                from: restingFrame,
                orientation: orientation,
                direction: direction
            )
            oldView.animator().alphaValue = 0.56
            newView.animator().frame = restingFrame
        } completionHandler: { [weak self, weak oldView, weak newView] in
            Task { @MainActor in
                oldView?.removeFromSuperview()
                newView?.removeFromSuperview()
                self?.endTransitionIsolation()
            }
        }
    }

    @discardableResult
    func handlePageScroll(with event: NSEvent) -> Bool {
        guard pageFlow.isPaging else { return false }
        let orientation = pageFlow.pageOrientation ?? .vertical
        let precise = event.hasPreciseScrollingDeltas
        let delta = pageAxisDelta(event, orientation: orientation, precise: precise)
        let isEnding = event.phase == .ended || event.phase == .cancelled
        if precise {
            if event.phase == .began {
                preciseGestureActive = true
                precisePageAttempted = false
            } else if !preciseGestureActive,
                      event.phase == .changed,
                      event.momentumPhase.isEmpty {
                preciseGestureActive = true
                precisePageAttempted = false
            }

            guard preciseGestureActive else { return true }
            if interactivePageSettling {
                precisePageAttempted = true
                if isEnding {
                    preciseGestureActive = false
                }
                return true
            }
            if let interactivePage {
                if isEnding {
                    finishInteractivePage(interactivePage)
                    preciseGestureActive = false
                } else if abs(delta) > 0.01 {
                    updateInteractivePage(interactivePage, delta: delta)
                }
                return true
            }
            if isEnding {
                preciseGestureActive = false
                return true
            }
            guard !precisePageAttempted, abs(delta) > 0.01 else { return true }
            precisePageAttempted = true
            let direction = delta > 0 ? -1 : 1
            guard beginInteractivePage(direction: direction, orientation: orientation) else {
                return true
            }
            if let interactivePage {
                updateInteractivePage(interactivePage, delta: delta)
            }
            return true
        }

        guard abs(delta) > 0.01, !pageTurnInFlight else { return true }
        pageTurnInFlight = true
        _ = pageTurn?(delta > 0 ? -1 : 1, true)
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

    private func pageAxisDelta(
        _ event: NSEvent,
        orientation: ReaderPageOrientation,
        precise: Bool
    ) -> CGFloat {
        switch orientation {
        case .horizontal:
            if precise {
                return CGFloat(event.scrollingDeltaX)
            }
            return CGFloat(event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY)
        case .vertical:
            if precise {
                return CGFloat(event.scrollingDeltaY)
            }
            return CGFloat(event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX)
        }
    }

    private func beginInteractivePage(
        direction: Int,
        orientation: ReaderPageOrientation
    ) -> Bool {
        guard interactivePage == nil,
              let before = snapshotImage(),
              let startOffset = documentScrollOffset else {
            return false
        }
        pageTurnRollbackOffset = startOffset
        guard pageTurn?(direction, false) == true else {
            pageTurnRollbackOffset = nil
            return false
        }
        let rollbackOffset = pageTurnRollbackOffset ?? startOffset
        displayIfNeeded()
        contentView.displayIfNeeded()
        documentView?.displayIfNeeded()
        guard let after = snapshotImage() else {
            scroll(to: rollbackOffset, animated: false)
            return false
        }

        let oldView = transitionImageView(image: before)
        let newView = transitionImageView(image: after)
        let restingFrame = bounds
        oldView.frame = restingFrame
        newView.frame = incomingFrame(
            from: restingFrame,
            orientation: orientation,
            direction: direction
        )
        configureIncomingView(newView, orientation: orientation, direction: direction)
        addSubview(oldView)
        addSubview(newView)
        beginTransitionIsolation()
        let transition = InteractivePageTransition(
            oldView: oldView,
            newView: newView,
            restingFrame: restingFrame,
            startOffset: rollbackOffset,
            direction: direction,
            orientation: orientation
        )
        interactivePage = transition
        applyInteractivePage(transition, progress: 0)
        return true
    }

    private func updateInteractivePage(
        _ transition: InteractivePageTransition,
        delta: CGFloat
    ) {
        guard interactivePage === transition else { return }
        let proposed = transition.translation + delta
        let extent = pageExtent(for: transition.orientation, frame: transition.restingFrame)
        transition.translation = transition.direction > 0
            ? min(0, max(-extent, proposed))
            : max(0, min(extent, proposed))
        let threshold = interactiveThreshold(for: extent)
        let progress = min(1, abs(transition.translation) / threshold)
        applyInteractivePage(transition, progress: progress)
    }

    private func finishInteractivePage(_ transition: InteractivePageTransition) {
        guard interactivePage === transition else { return }
        interactivePage = nil
        interactivePageSettling = true
        let extent = pageExtent(for: transition.orientation, frame: transition.restingFrame)
        let threshold = interactiveThreshold(for: extent)
        let shouldCommit = abs(transition.translation) >= threshold * 0.62
        let targetProgress = CGFloat(shouldCommit ? 1 : 0)
        let targetTranslation = shouldCommit
            ? -CGFloat(transition.direction) * threshold
            : 0
        let touchOffset = transition.orientation == .horizontal
            ? targetTranslation
            : -targetTranslation
        var oldFrame = transition.restingFrame
        let inset = transition.restingFrame.width * 0.008 * targetProgress
        let verticalInset = transition.restingFrame.height * 0.008 * targetProgress
        oldFrame = oldFrame.insetBy(dx: inset, dy: verticalInset)
        if transition.orientation == .horizontal {
            oldFrame.origin.x += touchOffset * 0.1
        } else {
            oldFrame.origin.y += touchOffset * 0.1
        }
        var newFrame = transition.restingFrame
        switch transition.orientation {
        case .horizontal:
            newFrame.origin.x += CGFloat(transition.direction) * extent + touchOffset
        case .vertical:
            newFrame.origin.y -= CGFloat(transition.direction) * extent - touchOffset
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = shouldCommit ? 0.2 : 0.24
            context.timingFunction = transitionTimingFunction()
            transition.oldView.animator().frame = oldFrame
            transition.oldView.animator().alphaValue = shouldCommit ? 0.56 : 1
            transition.newView.animator().frame = shouldCommit
                ? transition.restingFrame
                : incomingFrame(
                    from: transition.restingFrame,
                    orientation: transition.orientation,
                    direction: transition.direction
                )
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                transition.oldView.removeFromSuperview()
                transition.newView.removeFromSuperview()
                if !shouldCommit {
                    self.scroll(to: transition.startOffset, animated: false)
                }
                self.endTransitionIsolation()
                self.pageTurnRollbackOffset = nil
                self.interactivePageSettling = false
            }
        }
    }

    private func applyInteractivePage(
        _ transition: InteractivePageTransition,
        progress: CGFloat
    ) {
        let extent = pageExtent(for: transition.orientation, frame: transition.restingFrame)
        let touchOffset = transition.orientation == .horizontal
            ? transition.translation
            : -transition.translation
        var oldFrame = transition.restingFrame
        oldFrame = oldFrame.insetBy(
            dx: transition.restingFrame.width * 0.008 * progress,
            dy: transition.restingFrame.height * 0.008 * progress
        )
        if transition.orientation == .horizontal {
            oldFrame.origin.x += touchOffset * 0.1
        } else {
            oldFrame.origin.y += touchOffset * 0.1
        }
        var newFrame = transition.restingFrame
        switch transition.orientation {
        case .horizontal:
            newFrame.origin.x += CGFloat(transition.direction) * extent + touchOffset
        case .vertical:
            newFrame.origin.y -= CGFloat(transition.direction) * extent - touchOffset
        }
        transition.oldView.frame = oldFrame
        transition.oldView.alphaValue = 1 - progress * 0.44
        transition.newView.frame = newFrame
    }

    private func configureIncomingView(
        _ imageView: NSImageView,
        orientation: ReaderPageOrientation,
        direction: Int
    ) {
        imageView.layer?.shadowColor = NSColor.black.cgColor
        imageView.layer?.shadowOpacity = 0.32
        imageView.layer?.shadowRadius = 15
        imageView.layer?.shadowOffset = shadowOffset(
            orientation: orientation,
            direction: direction
        )
    }

    private func interactiveThreshold(for extent: CGFloat) -> CGFloat {
        max(96, extent * 0.3)
    }

    private func transitionTimingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.16, 0.82, 0.22, 1.0)
    }

    private func beginTransitionIsolation() {
        guard documentHiddenBeforeTransition == nil else { return }
        let wasHidden = documentView?.isHidden ?? false
        documentHiddenBeforeTransition = wasHidden
        documentView?.isHidden = true
    }

    private func endTransitionIsolation() {
        guard let wasHidden = documentHiddenBeforeTransition else { return }
        documentView?.isHidden = wasHidden
        if !wasHidden {
            documentView?.displayIfNeeded()
        }
        documentHiddenBeforeTransition = nil
    }

    private func pageExtent(for orientation: ReaderPageOrientation, frame: NSRect) -> CGFloat {
        orientation == .horizontal ? frame.width : frame.height
    }

    private var documentScrollOffset: CGFloat? {
        guard let documentView else { return nil }
        let maximum = max(0, documentView.frame.height - contentView.bounds.height)
        return min(max(contentView.bounds.origin.y, 0), maximum)
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
