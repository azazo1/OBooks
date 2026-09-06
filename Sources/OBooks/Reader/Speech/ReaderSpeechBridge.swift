import AppKit

@MainActor
final class ReaderSpeechBridge {
    let session: SpeechSession
    let follow = SpeechFollowController()
    var resolveRange: (SpeechPosition) -> NSRange? = { $0.range }
    var reveal: ((SpeechPosition) -> Void)?
    var restoreAnnotations: (() -> Void)?
    var highlightColor: () -> NSColor = { .systemYellow.withAlphaComponent(0.3) }
    var onSpeakingChanged: ((Bool) -> Void)?
    var overlayRect: NSRect = .zero
    private weak var textView: ReaderTextView?
    private weak var scrollView: ReaderScrollView?
    private var observers: [NSObjectProtocol] = []
    private var highlightRange: NSRange?

    init(session: SpeechSession) { self.session = session }

    func attach(textView: ReaderTextView, scrollView: ReaderScrollView) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        self.textView = textView
        self.scrollView = scrollView
        follow.onSuspend = { [weak scrollView] in scrollView?.interruptSpeechNavigation() }
        follow.onResume = { [weak self] in self?.revealCurrentPosition() }
        textView.onSpeechInteraction = { [weak self] active in
            self?.follow.setInteracting(active, source: "selection")
        }
        scrollView.onScrollInteractionChanged = { [weak self] active in
            self?.follow.setInteracting(active, source: "scroll")
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let textView = self.textView else { return }
                self.follow.selectionChanged(hasSelection: textView.selectedRanges.contains { $0.rangeValue.length > 0 })
            }
        })
        for (name, active) in [(NSScrollView.willStartLiveScrollNotification, true), (NSScrollView.didEndLiveScrollNotification, false)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: scrollView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow.setInteracting(active, source: "liveScroll") }
            })
        }
        observePresentationChanges()
        session.onPosition = { [weak self] _ in self?.refresh(followPosition: true) }
        session.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.textView?.allowsImagePreview = !state.isActive
            self.onSpeakingChanged?(state.isPlaying)
            self.follow.setPlaying(state.isPlaying)
            if !state.isActive { self.clearHighlight(); self.follow.reset() }
            if state == .failed { self.clearHighlight() }
        }
        session.onReveal = { [weak self] in self?.follow.resumeNow() }
    }

    func refresh(followPosition: Bool = false) {
        clearHighlight()
        guard session.state.isActive, let position = session.position else { return }
        if let range = resolveRange(position) { highlight(range) }
        if followPosition, session.state.isPlaying, follow.isFollowing { revealCurrentPosition() }
    }

    func highlight(_ range: NSRange) {
        clearHighlight()
        guard let textView, let manager = textView.layoutManager else { return }
        let valid = NSIntersectionRange(range, NSRange(location: 0, length: textView.string.utf16.count))
        guard valid.length > 0 else { return }
        manager.addTemporaryAttribute(.backgroundColor, value: highlightColor(), forCharacterRange: valid)
        highlightRange = valid
        textView.needsDisplay = true
    }

    func clearHighlight() {
        guard let range = highlightRange, let textView else { return }
        highlightRange = nil
        let valid = NSIntersectionRange(range, NSRange(location: 0, length: textView.string.utf16.count))
        if valid.length > 0 {
            textView.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: valid)
        }
        restoreAnnotations?()
        textView.needsDisplay = true
    }

    func revealCurrentPosition() {
        guard let position = session.position else { return }
        reveal?(position)
    }

    func handleWindowBecamePresentable() {
        guard session.state.isPlaying, follow.isFollowing else { return }
        guard let window = scrollView?.window else { return }
        guard window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) else { return }
        scrollView?.interruptSpeechNavigation()
        revealCurrentPosition()
    }

    private func observePresentationChanges() {
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated { self?.handlePresentationNotification(notification) }
            })
        }
    }

    private func handlePresentationNotification(_ notification: Notification) {
        if notification.name != NSApplication.didBecomeActiveNotification {
            guard let window = notification.object as? NSWindow, window === scrollView?.window else { return }
        }
        handleWindowBecamePresentable()
    }

    func teardown() {
        session.onPosition = nil
        session.onStateChanged = nil
        session.onReveal = nil
        session.pageForSentence = nil
        session.haltPlayback()
        follow.teardown()
        clearHighlight()
        textView?.allowsImagePreview = true
        textView?.onSpeechInteraction = nil
        scrollView?.onScrollInteractionChanged = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
