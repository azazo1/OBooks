import XCTest
@testable import OBooks

@MainActor
final class SpeechFollowControllerTests: XCTestCase {
    func testSelectionBlocksFollowingUntilClearedAndIdleWaitCompletes() async {
        let clock = FollowClock()
        let follow = SpeechFollowController { await clock.wait() }
        defer { follow.teardown() }
        var resumes = 0
        follow.onResume = { resumes += 1 }
        follow.setPlaying(true)
        follow.userInteraction()
        await clock.waitUntilArmed()
        follow.selectionChanged(hasSelection: true)
        await clock.advance()
        await drain()
        XCTAssertFalse(follow.isFollowing)
        XCTAssertEqual(resumes, 0)
        follow.selectionChanged(hasSelection: false)
        await clock.waitUntilArmed()
        await clock.advance()
        await drain()
        XCTAssertTrue(follow.isFollowing)
        XCTAssertEqual(resumes, 1)
    }

    func testLiveGestureAndPausePreventTimerFromResuming() async {
        let clock = FollowClock()
        let follow = SpeechFollowController { await clock.wait() }
        defer { follow.teardown() }
        follow.setPlaying(true)
        follow.setInteracting(true, source: "scroll")
        await drain()
        let pendingCount = await clock.pendingCount
        XCTAssertEqual(pendingCount, 0)
        follow.setInteracting(false, source: "scroll")
        await clock.waitUntilArmed()
        follow.setPlaying(false)
        await clock.advance()
        await drain()
        XCTAssertFalse(follow.isFollowing)
    }

    func testNewActivityInvalidatesOldTimerAndExplicitRevealCancelsWait() async {
        let clock = FollowClock()
        let follow = SpeechFollowController { await clock.wait() }
        defer { follow.teardown() }
        var resumes = 0
        follow.onResume = { resumes += 1 }
        follow.setPlaying(true)
        follow.userInteraction()
        await clock.waitUntilArmed()
        follow.userInteraction()
        follow.resumeNow()
        await clock.advance()
        await drain()
        XCTAssertTrue(follow.isFollowing)
        XCTAssertEqual(resumes, 1)
    }

    private func drain() async { for _ in 0..<20 { await Task.yield() } }
}

private actor FollowClock {
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    var pendingCount: Int { continuations.count }
    func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume() }
                else { continuations[id] = continuation }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func cancel(_ id: UUID) { continuations.removeValue(forKey: id)?.resume() }
    func waitUntilArmed() async {
        for _ in 0..<100 {
            if !continuations.isEmpty { return }
            await Task.yield()
        }
    }
    func advance() {
        let pending = continuations
        continuations = [:]
        pending.values.forEach { $0.resume() }
    }
}
