import Foundation

@MainActor
final class SpeechFollowController {
    private(set) var isFollowing = true
    private var isPlaying = false
    private var hasSelection = false
    private var interactions: Set<String> = []
    private var task: Task<Void, Never>?
    private var revision = 0
    private let wait: @Sendable () async throws -> Void
    var onResume: (() -> Void)?
    var onSuspend: (() -> Void)?

    init(wait: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(4)) }) {
        self.wait = wait
    }

    func setPlaying(_ value: Bool) {
        guard isPlaying != value else { return }
        isPlaying = value
        if !value { cancelTimer(); onSuspend?() }
        else if !isFollowing { arm() }
    }

    func userInteraction() {
        isFollowing = false
        onSuspend?()
        arm()
    }

    func setInteracting(_ value: Bool, source: String) {
        if value { interactions.insert(source) } else { interactions.remove(source) }
        userInteraction()
    }

    func selectionChanged(hasSelection: Bool) {
        guard self.hasSelection != hasSelection else { return }
        self.hasSelection = hasSelection
        userInteraction()
    }

    func resumeNow() {
        cancelTimer()
        isFollowing = true
        onResume?()
    }

    func reset() {
        cancelTimer()
        isFollowing = !hasSelection && interactions.isEmpty
    }

    func teardown() {
        cancelTimer()
        onResume = nil
        onSuspend = nil
    }

    private func arm() {
        cancelTimer()
        guard isPlaying, !hasSelection, interactions.isEmpty else { return }
        let expected = revision
        let wait = self.wait
        task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            do { try await wait() } catch { return }
            guard let self, !Task.isCancelled, self.revision == expected,
                  self.isPlaying, !self.hasSelection, self.interactions.isEmpty else { return }
            self.isFollowing = true
            self.onResume?()
        }
    }

    private func cancelTimer() {
        revision &+= 1
        task?.cancel()
        task = nil
    }
}
