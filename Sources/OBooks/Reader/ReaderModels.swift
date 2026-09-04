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

enum ReaderScrollScope: String, CaseIterable, Identifiable {
    case chapter
    case book

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chapter: return "章节内"
        case .book: return "全书连续"
        }
    }
}

enum ReaderPageOrientation: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vertical: return "垂直"
        case .horizontal: return "水平"
        }
    }
}

enum ReaderPageColumns: Int, CaseIterable, Identifiable {
    case single = 1
    case double = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .single: return "单栏"
        case .double: return "双栏"
        }
    }
}

enum ReaderFlowMode: Equatable {
    case scrolling(scope: ReaderScrollScope)
    case paging(orientation: ReaderPageOrientation, columns: ReaderPageColumns)

    var isPaging: Bool {
        if case .paging = self { return true }
        return false
    }

    var scrollScope: ReaderScrollScope? {
        if case .scrolling(let scope) = self { return scope }
        return nil
    }

    var pageOrientation: ReaderPageOrientation? {
        if case .paging(let orientation, _) = self { return orientation }
        return nil
    }

    var pageColumns: ReaderPageColumns {
        if case .paging(_, let columns) = self { return columns }
        return .single
    }

    var preferenceValue: String {
        switch self {
        case .scrolling(let scope):
            return "scrolling.\(scope.rawValue)"
        case .paging(let orientation, let columns):
            return "paging.\(orientation.rawValue).\(columns.rawValue)"
        }
    }

    init?(preferenceValue: String) {
        let parts = preferenceValue.split(separator: ".")
        guard let mode = parts.first else { return nil }
        switch mode {
        case "scrolling":
            guard parts.count == 2, let scope = ReaderScrollScope(rawValue: String(parts[1])) else { return nil }
            self = .scrolling(scope: scope)
        case "paging":
            guard parts.count == 3,
                  let orientation = ReaderPageOrientation(rawValue: String(parts[1])),
                  let rawColumns = Int(parts[2]),
                  let columns = ReaderPageColumns(rawValue: rawColumns) else { return nil }
            self = .paging(orientation: orientation, columns: columns)
        default:
            return nil
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
