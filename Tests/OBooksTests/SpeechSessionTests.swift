import XCTest
@testable import OBooks

@MainActor
final class SpeechSessionTests: XCTestCase {
    func testPauseResumesSameUtteranceAndKeepsPosition() async throws {
        let fixture = Fixture(["Hello world. Another sentence."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        await fixture.waitForSpeech()
        let call = try XCTUnwrap(fixture.engine.calls.last)
        fixture.engine.onEvent?(.range(call.id, NSRange(location: 6, length: 5)))
        let position = fixture.session.position
        fixture.session.pause()
        XCTAssertEqual(fixture.session.state, .paused)
        fixture.session.resume()
        XCTAssertEqual(fixture.session.state, .playing)
        XCTAssertEqual(fixture.engine.calls.count, 1)
        XCTAssertEqual(fixture.session.position, position)
    }

    func testMinimizedPlayerKeepsPlayingAcrossChaptersAndRestoresWithoutRestart() async throws {
        let fixture = Fixture(["First.", "Next."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        await fixture.waitForSpeech()
        fixture.session.minimizePlayer()
        XCTAssertFalse(fixture.session.isPlayerVisible)
        XCTAssertEqual(fixture.session.state, .playing)
        fixture.engine.finish()
        await fixture.waitForSpeech(count: 2)
        XCTAssertEqual(fixture.session.sectionIndex, 1)
        XCTAssertTrue(fixture.session.isMinimized)
        let position = fixture.session.position
        fixture.session.restorePlayer()
        XCTAssertTrue(fixture.session.isPlayerVisible)
        XCTAssertEqual(fixture.session.state, .playing)
        XCTAssertEqual(fixture.session.position, position)
        XCTAssertEqual(fixture.engine.calls.count, 2)
    }

    func testRestoringMinimizedPausedPlayerKeepsExpansionAndAudioPaused() async {
        let fixture = Fixture(["Hello world."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        await fixture.waitForSpeech()
        fixture.session.isExpanded = true
        fixture.session.pause()
        let position = fixture.session.position
        fixture.session.minimizePlayer()
        fixture.session.restorePlayer()
        XCTAssertTrue(fixture.session.isPlayerVisible)
        XCTAssertTrue(fixture.session.isExpanded)
        XCTAssertEqual(fixture.session.state, .paused)
        XCTAssertEqual(fixture.session.position, position)
        XCTAssertEqual(fixture.engine.calls.count, 1)
        fixture.session.minimizePlayer()
        fixture.session.stop()
        XCTAssertFalse(fixture.session.isMinimized)
        XCTAssertFalse(fixture.session.isPlayerVisible)
    }

    func testChangedRateRestartsAtCurrentWordAndIgnoresOldEvents() async throws {
        let fixture = Fixture(["Hello world. Another sentence."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        await fixture.waitForSpeech()
        let old = try XCTUnwrap(fixture.engine.calls.last)
        fixture.engine.onEvent?(.range(old.id, NSRange(location: 6, length: 5)))
        fixture.session.setRate(1.5)
        let next = try XCTUnwrap(fixture.engine.calls.last)
        XCTAssertEqual(next.text, "world.")
        XCTAssertEqual(next.rate, 1.5)
        fixture.engine.onEvent?(.finished(old.id))
        fixture.engine.onEvent?(.cancelled(old.id))
        fixture.engine.onEvent?(.range(old.id, NSRange(location: 0, length: 5)))
        XCTAssertEqual(fixture.session.position?.range.location, 6)
        XCTAssertEqual(fixture.session.state, .playing)
        fixture.engine.onEvent?(.range(next.id, NSRange(location: 0, length: 5)))
        XCTAssertEqual(fixture.session.position?.range, NSRange(location: 6, length: 5))
    }

    func testVoiceChangeWhilePausedDoesNotStartAudio() async throws {
        let fixture = Fixture(["Hello world."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        await fixture.waitForSpeech()
        fixture.session.pause()
        fixture.session.setVoice("test-voice")
        XCTAssertEqual(fixture.session.state, .paused)
        XCTAssertEqual(fixture.engine.calls.count, 1)
        fixture.session.resume()
        XCTAssertEqual(fixture.engine.calls.last?.voice, "test-voice")
        XCTAssertEqual(fixture.engine.calls.count, 2)
    }

    func testCrossChapterSkipsEmptyTextAndEndsAtBookBoundary() async throws {
        let fixture = Fixture(["First.", "\u{FFFC}\n", "Last."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        await fixture.waitForSpeech()
        fixture.engine.finish()
        await fixture.waitForSpeech(count: 2)
        XCTAssertEqual(fixture.session.sectionIndex, 2)
        XCTAssertEqual(fixture.session.position?.spineID, "section-2")
        XCTAssertEqual(fixture.engine.calls.last?.text, "Last.")
        fixture.engine.finish()
        XCTAssertEqual(fixture.session.state, .ended)
        XCTAssertFalse(fixture.session.state.isActive)
    }

    func testHaltPlaybackStopsEngineWithoutPublishingIdle() async throws {
        let fixture = Fixture(["Hello world."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        await fixture.waitForSpeech()
        fixture.session.isExpanded = true
        let stops = fixture.engine.stopCount
        fixture.session.haltPlayback()
        XCTAssertEqual(fixture.session.state, .playing)
        XCTAssertTrue(fixture.session.isExpanded)
        XCTAssertGreaterThan(fixture.engine.stopCount, stops)
        let call = try XCTUnwrap(fixture.engine.calls.last)
        fixture.engine.onEvent?(.finished(call.id))
        XCTAssertEqual(fixture.session.state, .playing)
        fixture.session.stop()
        XCTAssertEqual(fixture.session.state, .idle)
        XCTAssertFalse(fixture.session.isExpanded)
    }

    func testRapidSeekAndStopRejectPendingLoadsAndOldCallbacks() async throws {
        let fixture = Fixture(["First. Second.", "Elsewhere."])
        defer { fixture.close() }
        fixture.session.start(section: 0)
        fixture.session.start(section: 1)
        await fixture.waitForSpeech()
        XCTAssertEqual(fixture.engine.calls.count, 1)
        XCTAssertEqual(fixture.engine.calls.last?.text, "Elsewhere.")
        let call = try XCTUnwrap(fixture.engine.calls.last)
        fixture.session.stop()
        fixture.engine.onEvent?(.started(call.id))
        fixture.engine.onEvent?(.finished(call.id))
        XCTAssertEqual(fixture.session.state, .idle)
        XCTAssertNil(fixture.session.position)
    }

    func testOwnerPausesPreviousWindow() async {
        let owner = SpeechPlaybackOwner()
        let first = Fixture(["First."])
        let second = Fixture(["Second."])
        defer { first.close(); second.close() }
        first.session.playbackOwner = owner
        second.session.playbackOwner = owner
        first.session.start(section: 0)
        await first.waitForSpeech()
        second.session.start(section: 0)
        await second.waitForSpeech()
        XCTAssertEqual(first.session.state, .paused)
        XCTAssertEqual(second.session.state, .playing)
    }

    func testPausedParagraphStepAndCharacterStart() async {
        let fixture = Fixture(["Hello world. Again.\nNext paragraph. Last sentence."])
        defer { fixture.close() }
        fixture.session.start(section: 0, offset: 6)
        await fixture.waitForSpeech()
        XCTAssertEqual(fixture.engine.calls.last?.text, "world.")
        fixture.session.pause()
        fixture.session.step(1, byParagraph: true)
        XCTAssertEqual(fixture.session.state, .paused)
        XCTAssertEqual(fixture.engine.calls.count, 1)
        XCTAssertEqual(fixture.session.sentences[fixture.session.sentenceIndex].text, "Next paragraph.")
    }

    func testFailedChapterCanBeRetried() async {
        let fixture = Fixture(["First."])
        defer { fixture.close() }
        var fail = true
        fixture.session.configure(spineIDs: ["one"], title: { _ in "" }) { _ in
            if fail { throw CocoaError(.fileReadCorruptFile) }
            return "Recovered."
        }
        fixture.session.start(section: 0)
        for _ in 0..<50 where fixture.session.state != .failed { await Task.yield() }
        XCTAssertEqual(fixture.session.state, .failed)
        fail = false
        fixture.session.resume()
        await fixture.waitForSpeech()
        XCTAssertEqual(fixture.engine.calls.last?.text, "Recovered.")
    }

    func testUnavailableSpeechDoesNotLeavePlayerPreparingForever() async throws {
        let engine = FakeSpeechEngine()
        engine.startsAutomatically = false
        let session = SpeechSession(engine: engine, startupTimeout: .milliseconds(20))
        defer { session.stop() }
        session.configure(spineIDs: ["one"], title: { _ in "" }, loadText: { _ in "Hello." })
        session.start(section: 0)
        for _ in 0..<100 where session.state != .failed { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .failed)
        XCTAssertNotNil(session.errorMessage)
        let stale = try XCTUnwrap(engine.calls.last)
        engine.onEvent?(.started(stale.id))
        XCTAssertEqual(session.state, .failed)
        engine.startsAutomatically = true
        session.resume()
        for _ in 0..<100 where session.state != .playing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .playing)
    }

    @MainActor
    private final class Fixture {
        let engine = FakeSpeechEngine()
        let session: SpeechSession
        let suite = "OBooks.SpeechTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init(_ chapters: [String]) {
            defaults = UserDefaults(suiteName: suite)!
            session = SpeechSession(engine: engine, defaults: defaults)
            session.configure(spineIDs: chapters.indices.map { "section-\($0)" },
                title: { "Chapter \($0)" }, loadText: { chapters[$0] })
        }

        func waitForSpeech(count: Int = 1) async {
            for _ in 0..<100 {
                if engine.calls.count >= count { return }
                try? await Task.sleep(for: .milliseconds(5))
            }
            XCTFail("等待语音请求超时")
        }

        func close() {
            session.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}

@MainActor
final class FakeSpeechEngine: SpeechEngine {
    struct Call {
        let id: UUID
        let text: String
        let voice: String?
        let rate: Float
    }
    var onEvent: ((SpeechEngineEvent) -> Void)?
    var calls: [Call] = []
    var startsAutomatically = true
    var stopCount = 0
    func speak(text: String, voiceIdentifier: String?, rate: Float, id: UUID) {
        calls.append(Call(id: id, text: text, voice: voiceIdentifier, rate: rate))
        if startsAutomatically { onEvent?(.started(id)) }
    }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() { stopCount += 1 }
    func finish() { if let id = calls.last?.id { onEvent?(.finished(id)) } }
}
