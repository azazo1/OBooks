import AppKit
import QuartzCore

@MainActor
final class ReaderScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    var pageTurn: ((Int, Bool) -> Bool)?
    var pageFlow: ReaderFlowMode = .scrolling(scope: .chapter)

    private var scrollTargetY: CGFloat?
    private var refreshLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var pageTurnInFlight = false
    private var preciseGestureActive = false
    private var preciseGestureDelta: CGFloat = 0
    private var precisePageCommitted = false
    private var pageTurnCooldownTask: Task<Void, Never>?
    private let responseDuration: CFTimeInterval = 0.16
    private let preciseTurnThreshold: CGFloat = 42
    private let pageTurnCooldown: Duration = .milliseconds(260)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            prepareForProgrammaticScroll()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        if pageFlow.isPaging {
            _ = handlePageScroll(with: event)
            return
        }
        guard !handleScrollWheel(with: event) else { return }
        super.scrollWheel(with: event)
    }

    func notifyUserScroll() {
        onUserScroll?()
    }

    func configure(flow: ReaderFlowMode) {
        guard pageFlow != flow else { return }
        pageFlow = flow
        resetPreciseGesture()
        cancelPageTurn()
        prepareForProgrammaticScroll()
    }

    @discardableResult
    func beginPageTurn() -> Bool {
        guard !pageTurnInFlight else { return false }
        pageTurnInFlight = true
        stopSmoothScroll()
        return true
    }

    var isPageTurnInFlight: Bool {
        pageTurnInFlight
    }

    func finishPageTurn(after delay: Duration? = nil) {
        pageTurnCooldownTask?.cancel()
        guard pageTurnInFlight else { return }
        guard let delay else {
            pageTurnInFlight = false
            return
        }
        pageTurnCooldownTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pageTurnInFlight = false
            self?.pageTurnCooldownTask = nil
        }
    }

    func cancelPageTurn() {
        pageTurnCooldownTask?.cancel()
        pageTurnCooldownTask = nil
        pageTurnInFlight = false
    }

    @discardableResult
    func handlePageScroll(with event: NSEvent) -> Bool {
        guard pageFlow.isPaging else { return false }
        let orientation = pageFlow.pageOrientation ?? .vertical
        let precise = event.hasPreciseScrollingDeltas
        let delta = pageAxisDelta(event, orientation: orientation, precise: precise)

        if precise {
            return handlePrecisePageScroll(delta: delta, event: event)
        }

        guard abs(delta) > 0.01, !pageTurnInFlight else { return true }
        let direction = delta > 0 ? -1 : 1
        guard beginPageTurn() else { return true }
        if pageTurn?(direction, true) == true {
            finishPageTurn(after: pageTurnCooldown)
        } else {
            cancelPageTurn()
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
        let maximum = maximumScrollOffset()
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
        cancelPageTurn()
        resetPreciseGesture()
    }

    private func handlePrecisePageScroll(delta: CGFloat, event: NSEvent) -> Bool {
        if event.phase == .began || (!preciseGestureActive && event.phase == .changed && event.momentumPhase.isEmpty) {
            preciseGestureActive = true
            preciseGestureDelta = 0
            precisePageCommitted = false
        }
        guard preciseGestureActive else { return true }

        if event.phase == .cancelled {
            resetPreciseGesture()
            return true
        }

        if !precisePageCommitted, abs(delta) > 0.01 {
            preciseGestureDelta += delta
            if abs(preciseGestureDelta) >= preciseTurnThreshold,
               !pageTurnInFlight {
                turnForPreciseGesture()
            }
        }

        if event.phase == .ended {
            if !precisePageCommitted,
               abs(preciseGestureDelta) >= preciseTurnThreshold * 0.62,
               !pageTurnInFlight {
                turnForPreciseGesture()
            }
            resetPreciseGesture()
        }
        return true
    }

    private func turnForPreciseGesture() {
        let direction = preciseGestureDelta > 0 ? -1 : 1
        precisePageCommitted = true
        guard beginPageTurn() else { return }
        if pageTurn?(direction, true) == true {
            finishPageTurn(after: pageTurnCooldown)
        } else {
            cancelPageTurn()
        }
    }

    private func resetPreciseGesture() {
        preciseGestureActive = false
        preciseGestureDelta = 0
        precisePageCommitted = false
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

        let current = currentScrollOffset()
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
        let point = pageFlow.pageOrientation == .horizontal
            ? NSPoint(x: y, y: contentView.bounds.origin.y)
            : NSPoint(x: contentView.bounds.origin.x, y: y)
        contentView.scroll(to: point)
        reflectScrolledClipView(contentView)
    }

    private func maximumScrollOffset() -> CGFloat {
        guard let documentView else { return 0 }
        if pageFlow.pageOrientation == .horizontal {
            return max(0, documentView.frame.width - contentView.bounds.width)
        }
        return max(0, documentView.frame.height - contentView.bounds.height)
    }

    private func currentScrollOffset() -> CGFloat {
        pageFlow.pageOrientation == .horizontal
            ? contentView.bounds.origin.x
            : contentView.bounds.origin.y
    }

    private func stopSmoothScroll() {
        refreshLink?.invalidate()
        refreshLink = nil
        scrollTargetY = nil
        lastFrameTimestamp = nil
    }
}
