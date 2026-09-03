import Foundation

enum ReadingFlow: String, CaseIterable, Identifiable {
    case paginated
    case scrolled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paginated: return "分页"
        case .scrolled: return "滚动"
        }
    }
}

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

enum ReaderAction: Equatable {
    case nextPage
    case previousPage
    case toggleSpeech
    case stopSpeech
    case speakText(String)
}

struct ReaderAnnotation: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: String
}
struct ReaderCommand: Equatable, Identifiable {
    let id = UUID()
    let action: ReaderAction
}
