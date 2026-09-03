import AVFoundation
import Foundation

@MainActor
final class SpeechService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    var onRange: ((NSRange) -> Void)?
    var onFinished: (() -> Void)?
    var onStateChanged: ((Bool) -> Void)?

    func speak(text: String, voiceIdentifier: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }
        utterance.rate = rate
        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        setSpeaking(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        setSpeaking(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        onRange?(characterRange)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        setSpeaking(false)
        onFinished?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        setSpeaking(false)
    }

    private func setSpeaking(_ value: Bool) {
        guard isSpeaking != value else { return }
        isSpeaking = value
        onStateChanged?(value)
    }
}
