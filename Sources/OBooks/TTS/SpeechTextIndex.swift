import Foundation
import NaturalLanguage

struct SpeechSentence: Identifiable, Equatable {
    let id: Int
    let paragraph: Int
    let range: NSRange
    let text: String
}

struct SpeechPosition: Equatable {
    let sectionIndex: Int
    let spineID: String
    let range: NSRange
}

struct SpeechTextIndex {
    let sentences: [SpeechSentence]
    let language: String?

    init(text: String) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(4000)))
        language = recognizer.dominantLanguage?.rawValue
        let source = text as NSString
        let tokenizer = NLTokenizer(unit: .sentence)
        var result: [SpeechSentence] = []
        var paragraph = 0
        // 按原文范围分割, 避免移除附件或空白后破坏 TextKit 的 UTF-16 偏移.
        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: "\u{FFFC}"))
        var start = 0
        while start < source.length {
            let separator = source.rangeOfCharacter(from: separators, range: NSRange(location: start, length: source.length - start))
            let end = separator.location == NSNotFound ? source.length : separator.location
            let block = source.substring(with: NSRange(location: start, length: end - start))
            tokenizer.string = block
            if let blockLanguage = NLLanguageRecognizer.dominantLanguage(for: block) {
                tokenizer.setLanguage(blockLanguage)
            }
            tokenizer.enumerateTokens(in: block.startIndex..<block.endIndex) { range, _ in
                let original = NSRange(range, in: block)
                let token = (block as NSString).substring(with: original) as NSString
                let meaningful = token.rangeOfCharacter(from: .whitespacesAndNewlines.inverted)
                guard meaningful.location != NSNotFound else { return true }
                let last = token.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: .backwards)
                let trimmed = NSRange(location: meaningful.location, length: NSMaxRange(last) - meaningful.location)
                let value = token.substring(with: trimmed)
                guard value.rangeOfCharacter(from: .alphanumerics) != nil else { return true }
                result.append(SpeechSentence(
                    id: result.count, paragraph: paragraph,
                    range: NSRange(location: start + original.location + trimmed.location, length: trimmed.length),
                    text: value
                ))
                return true
            }
            paragraph += 1
            start = separator.location == NSNotFound ? source.length : NSMaxRange(separator)
        }
        sentences = result
    }

    func sentence(at offset: Int) -> Int? {
        sentences.firstIndex { NSMaxRange($0.range) > offset }
    }
}
