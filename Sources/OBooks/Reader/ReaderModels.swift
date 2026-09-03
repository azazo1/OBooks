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
    case paper
    case ivory
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: return "白色"
        case .ivory: return "护眼"
        case .dark: return "深色"
        }
    }
}

enum ReaderAction: Equatable {
    case nextPage
    case previousPage
    case toggleSpeech
    case stopSpeech
}

struct ReaderCommand: Equatable, Identifiable {
    let id = UUID()
    let action: ReaderAction
}
