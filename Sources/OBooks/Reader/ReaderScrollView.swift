import AppKit
import QuartzCore

@MainActor
struct ReaderPageTurn {
    let rollback: () -> Void
}

@MainActor
final class ReaderScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    var onScrollInteractionChanged: ((Bool) -> Void)?
    var pageTurn: ((Int) -> ReaderPageTurn?)?
    var onPageTurnCompleted: (() -> Void)?
    var onViewportSizeChanged: ((Int?, CGFloat?) -> Void)?
    private(set) var pageFlow: ReaderFlowMode = .scrolling(scope: .chapter)
    private(set) var scrollTargetY: CGFloat?
    private var speechScroll = false
    private var refreshLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var transition: PageTransition?
    private var preparingPage = false
    private var gesture: ReaderPageTurnGesture?
    private var gestureRejected = false
    private var lastWheelTurn: TimeInterval = -.infinity
    var onKeyboardNavigate: ((Int) -> Void)?
    private var keyMonitor: Any?

    var isPageTransitionActive: Bool { preparingPage || transition != nil }

    @MainActor
    private final class PageTransition {
        let oldView: NSImageView
        let newView: NSImageView
        let frame: NSRect
        let direction: Int
        let orientation: ReaderPageOrientation
        let turn: ReaderPageTurn
        let documentWasHidden: Bool
        let isSpeech: Bool
        var settlement: Bool?

        init(oldView: NSImageView, newView: NSImageView, frame: NSRect,
             direction: Int, orientation: ReaderPageOrientation,
             turn: ReaderPageTurn, documentWasHidden: Bool, isSpeech: Bool) {
            self.oldView = oldView
            self.newView = newView
            self.frame = frame
            self.direction = direction
            self.orientation = orientation
            self.turn = turn
            self.documentWasHidden = documentWasHidden
            self.isSpeech = isSpeech
        }

        var extent: CGFloat { orientation == .horizontal ? frame.width : frame.height }

        func frames(progress: CGFloat) -> (old: NSRect, new: NSRect) {
            let displacement = CGFloat(direction) * extent
            var old = frame
            var new = frame
            if orientation == .horizontal {
                old.origin.x -= displacement * progress
                new.origin.x += displacement * (1 - progress)
            } else {
                // NSScrollView 使用翻转坐标系, 下一页从下方进入.
                old.origin.y -= displacement * progress
                new.origin.y += displacement * (1 - progress)
            }
            return (old, new)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { prepareForProgrammaticScroll() }
        installKeyMonitor()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 0.5
            || abs(frame.height - newSize.height) > 0.5
        if changed { prepareForProgrammaticScroll() }
        let location = (documentView as? ReaderTextView)?.visibleCharacterLocation()
        super.setFrameSize(newSize)
        if changed {
            let viewportOffset = (documentView as? ReaderTextView)?.viewportOffset(
                forCharacter: location ?? 0
            )
            onViewportSizeChanged?(location, viewportOffset)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase.contains(.began) || event.momentumPhase.contains(.began) {
            onScrollInteractionChanged?(true)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) {
            onScrollInteractionChanged?(false)
        }
        onUserScroll?()
        if handlePageScroll(with: event) || handleScrollWheel(with: event) { return }
        super.scrollWheel(with: event)
    }

    func configure(flow: ReaderFlowMode) {
        guard pageFlow != flow else { return }
        prepareForProgrammaticScroll()
        pageFlow = flow
        verticalScrollElasticity = flow.isPaging ? .none : .automatic
        horizontalScrollElasticity = .none
    }

    func handleKeyboardNavigate(_ direction: Int) {
        if let onKeyboardNavigate {
            onKeyboardNavigate(direction)
            return
        }
        _ = turnPage(direction: direction)
    }

    private func installKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, window?.isKeyWindow == true else { return event }
        guard !ReaderKeyNavigation.isEditingText(in: window) else { return event }
        guard let direction = ReaderKeyNavigation.pageDirection(for: event) else { return event }
        handleKeyboardNavigate(direction)
        return nil
    }

    @discardableResult
    func turnPage(direction: Int, animated: Bool = true) -> Bool {
        onUserScroll?()
        if let transition {
            completeTransition(transition, commit: transition.settlement ?? false)
        }
        gesture = nil
        stopSmoothScroll()
        guard pageFlow.isPaging else { return pageTurn?(direction) != nil }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            preparingPage = true
            let turned = pageTurn?(direction) != nil
            preparingPage = false
            onPageTurnCompleted?()
            return turned
        }
        guard let transition = beginTransition(direction: direction) else { return false }
        settle(transition, commit: true)
        return true
    }

    @discardableResult
    func handlePageScroll(with event: NSEvent) -> Bool {
        guard pageFlow.isPaging else { return false }
        // 惯性属于刚结束的手势, 不能再次触发翻页.
        guard event.momentumPhase.isEmpty else { return true }
        let horizontal = pageFlow.pageOrientation == .horizontal
        let primary = CGFloat(horizontal ? event.scrollingDeltaX : event.scrollingDeltaY)
        let secondary = CGFloat(horizontal ? event.scrollingDeltaY : event.scrollingDeltaX)
        guard event.hasPreciseScrollingDeltas, !event.phase.isEmpty else {
            let delta = abs(primary) > 0.01 ? primary : secondary
            guard abs(delta) > 0.01, event.timestamp - lastWheelTurn >= 0.25 else { return true }
            lastWheelTurn = event.timestamp
            _ = turnPage(direction: delta < 0 ? 1 : -1)
            return true
        }

        if event.phase.contains(.began) {
            if let transition {
                completeTransition(transition, commit: transition.settlement ?? false)
            }
            gesture = ReaderPageTurnGesture()
            gestureRejected = false
        }
        let cancelled = event.phase.contains(.cancelled)
        let ended = event.phase.contains(.ended) || cancelled
        if gesture == nil, event.phase.contains(.changed), transition == nil {
            gesture = ReaderPageTurnGesture()
            gestureRejected = false
        }
        guard var gesture else { return true }
        if transition == nil, abs(secondary) > max(6, abs(primary) * 1.25) {
            gestureRejected = true
        }
        if !gestureRejected {
            if abs(primary) > 0.01 {
                gesture.update(delta: primary, timestamp: event.timestamp)
                self.gesture = gesture
            }
            if transition == nil, !ended, let direction = gesture.direction {
                if beginTransition(direction: direction) == nil { gestureRejected = true }
            }
            if let transition, transition.settlement == nil {
                let frames = transition.frames(progress: gesture.progress(
                    direction: transition.direction, extent: transition.extent
                ))
                transition.oldView.frame = frames.old
                transition.newView.frame = frames.new
                if ended {
                    settle(transition, commit: !cancelled && gesture.shouldCommit(
                        direction: transition.direction,
                        extent: transition.extent,
                        timestamp: event.timestamp
                    ))
                }
            }
        }
        if ended { self.gesture = nil }
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
        scrollTargetY = min(max(currentTarget - CGFloat(event.scrollingDeltaY) * 36, 0), maximum)
        startDisplayLink()
        return true
    }

    func scroll(to offset: CGFloat, animated: Bool, forSpeech: Bool = false) {
        let step = max(1, contentView.bounds.height)
        let maximum = max(0, (documentView?.frame.height ?? 0) - contentView.bounds.height)
        var target = min(max(offset, 0), maximum)
        if pageFlow.isPaging {
            target = (target / step).rounded() * step
            target = min(max(target, 0), maximum)
        }
        guard animated, !pageFlow.isPaging, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopSmoothScroll()
            setScrollOffset(target)
            return
        }
        scrollTargetY = target
        speechScroll = forSpeech
        startDisplayLink()
    }

    func interruptSpeechNavigation() {
        if speechScroll { stopSmoothScroll() }
        if let transition, transition.isSpeech { completeTransition(transition, commit: true) }
    }

    func transitionContent(direction: Int, update: @escaping () -> ReaderPageTurn?) {
        prepareForProgrammaticScroll()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            _ = update()
            onPageTurnCompleted?()
            return
        }
        guard let transition = beginTransition(direction: direction, update: update) else { return }
        settle(transition, commit: true)
    }

    func prepareForProgrammaticScroll() {
        stopSmoothScroll()
        gesture = nil
        if let transition {
            completeTransition(transition, commit: transition.settlement ?? false)
        }
    }

    private func beginTransition(direction: Int, update: (() -> ReaderPageTurn?)? = nil) -> PageTransition? {
        guard transition == nil, !preparingPage else { return nil }
        stopSmoothScroll()
        let before = snapshotImage()
        preparingPage = true
        guard let turn = update?() ?? (update == nil ? pageTurn?(direction) : nil) else {
            preparingPage = false
            return nil
        }
        guard let before, let after = snapshotImage() else {
            turn.rollback()
            preparingPage = false
            onPageTurnCompleted?()
            return nil
        }
        let oldView = imageView(before)
        let newView = imageView(after)
        let transition = PageTransition(
            oldView: oldView, newView: newView, frame: bounds,
            direction: direction, orientation: pageFlow.pageOrientation ?? .vertical,
            turn: turn, documentWasHidden: documentView?.isHidden ?? false, isSpeech: update != nil
        )
        let frames = transition.frames(progress: 0)
        oldView.frame = frames.old
        newView.frame = frames.new
        addSubview(oldView)
        addSubview(newView)
        documentView?.isHidden = true
        self.transition = transition
        preparingPage = false
        return transition
    }

    private func settle(_ transition: PageTransition, commit: Bool) {
        transition.settlement = commit
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            completeTransition(transition, commit: commit)
            return
        }
        let frames = transition.frames(progress: commit ? 1 : 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.75, 0.25, 1)
            transition.oldView.animator().frame = frames.old
            transition.newView.animator().frame = frames.new
        } completionHandler: { [weak self, weak transition] in
            Task { @MainActor in
                guard let self, let transition, self.transition === transition else { return }
                self.completeTransition(transition, commit: commit)
            }
        }
    }

    private func completeTransition(_ transition: PageTransition, commit: Bool) {
        guard self.transition === transition else { return }
        if !commit { transition.turn.rollback() }
        documentView?.isHidden = transition.documentWasHidden
        documentView?.displayIfNeeded()
        transition.oldView.removeFromSuperview()
        transition.newView.removeFromSuperview()
        self.transition = nil
        onPageTurnCompleted?()
    }

    private func snapshotImage() -> NSImage? {
        displayIfNeeded()
        contentView.displayIfNeeded()
        documentView?.displayIfNeeded()
        guard bounds.width > 1, bounds.height > 1,
              let representation = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func imageView(_ image: NSImage) -> NSImageView {
        let view = NSImageView(image: image)
        view.imageScaling = .scaleAxesIndependently
        view.wantsLayer = true
        return view
    }

    private func startDisplayLink() {
        guard refreshLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        refreshLink = link
        lastFrameTimestamp = nil
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
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
        let frameDuration = lastFrameTimestamp.map {
            min(max(link.timestamp - $0, 1.0 / 240.0), 1.0 / 30.0)
        } ?? max(link.duration, 1.0 / 120.0)
        lastFrameTimestamp = link.timestamp
        let blend = 1 - pow(0.01, frameDuration / 0.12)
        setScrollOffset(current + distance * blend)
    }

    private func setScrollOffset(_ y: CGFloat) {
        contentView.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }

    private func stopSmoothScroll() {
        refreshLink?.invalidate()
        refreshLink = nil
        scrollTargetY = nil
        speechScroll = false
        lastFrameTimestamp = nil
    }
}
