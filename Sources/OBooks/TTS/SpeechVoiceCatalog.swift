import AVFoundation
import Foundation

struct SpeechVoice: Identifiable {
    let id: String
    let name: String
    let language: String
    let quality: String

    var label: String { quality.isEmpty ? name : "\(name) (\(quality))" }
}

enum SpeechVoiceCatalog {
    static func installed() -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            SpeechVoice(id: voice.identifier, name: voice.name, language: voice.language,
                quality: voice.quality == .premium ? "优质" : voice.quality == .enhanced ? "增强" : "")
        }.sorted {
            $0.language == $1.language
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.language < $1.language
        }
    }

    static func defaultIdentifier(language: String?) -> String? {
        AVSpeechSynthesisVoice(language: language ?? Locale.current.language.languageCode?.identifier)?.identifier
    }
}
