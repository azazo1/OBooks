import Foundation

enum ReadingTheme: String, CaseIterable, Identifiable {
    case original
    case quiet
    case paper
    case bold
    case calm
    case focus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "原始"
        case .quiet: return "安静"
        case .paper: return "纸张"
        case .bold: return "粗体"
        case .calm: return "平静"
        case .focus: return "专注"
        }
    }
}

struct ReadingPosition: Codable, Hashable, Sendable {
    let spineID: String
    let characterOffset: Int

    init(spineID: String, characterOffset: Int) {
        self.spineID = spineID
        self.characterOffset = characterOffset
    }
}

enum ReaderAction: Equatable {
    case nextPage
    case previousPage
    case seek(Double, animated: Bool)
    case toggleSpeech
    case stopSpeech
}

struct ReaderAnnotation: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: String
    let sectionIndex: Int
    let range: NSRange

    init(text: String, kind: String, sectionIndex: Int, range: NSRange) {
        self.text = text
        self.kind = kind
        self.sectionIndex = sectionIndex
        self.range = range
    }
}

struct ReaderCommand: Equatable, Identifiable {
    let id = UUID()
    let action: ReaderAction
}
