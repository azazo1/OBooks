import AVFoundation
import Foundation

enum SpeechEngineEvent {
    case started(UUID)
    case range(UUID, NSRange)
    case finished(UUID)
    case paused(UUID)
    case cancelled(UUID)
}

@MainActor
protocol SpeechEngine: AnyObject {
    var onEvent: ((SpeechEngineEvent) -> Void)? { get set }
    func speak(text: String, voiceIdentifier: String?, rate: Float, id: UUID)
    func pause() -> Bool
    func resume() -> Bool
    func stop()
}

@MainActor
final class SpeechService: NSObject, SpeechEngine, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var activeID: UUID?
    var onEvent: ((SpeechEngineEvent) -> Void)?

    func speak(text: String, voiceIdentifier: String?, rate: Float, id: UUID) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate))
        activeUtterance = utterance
        activeID = id
        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }

    func pause() -> Bool { synthesizer.pauseSpeaking(at: .immediate) }
    func resume() -> Bool { synthesizer.continueSpeaking() }

    func stop() {
        activeID = nil
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func id(for utterance: AVSpeechUtterance) -> UUID? {
        utterance === activeUtterance ? activeID : nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if let id = id(for: utterance) { onEvent?(.started(id)) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if let id = id(for: utterance) { onEvent?(.range(id, characterRange)) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard let id = id(for: utterance) else { return }
        activeID = nil
        activeUtterance = nil
        onEvent?(.finished(id))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        if let id = id(for: utterance) { onEvent?(.paused(id)) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if let id = id(for: utterance) { onEvent?(.cancelled(id)) }
    }
}
