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
    let viewportOffset: Double?

    init(spineID: String, characterOffset: Int, viewportOffset: Double? = nil) {
        self.spineID = spineID
        self.characterOffset = characterOffset
        self.viewportOffset = viewportOffset
    }
}

enum ReaderAction: Equatable {
    case nextPage
    case previousPage
    case seek(Double, animated: Bool)
    case toggleSpeech
    case stopSpeech
    case speechSentence(Int)
    case speechStep(Int, paragraph: Bool)
    case speechRate(Double)
    case speechVoice(String)
    case revealSpeech
}

struct ReaderAnnotation: Identifiable, Equatable, Codable, Hashable {
    let id: UUID
    let text: String
    let quote: String?
    let kind: String
    let sectionIndex: Int
    let range: NSRange

    init(
        id: UUID = UUID(),
        text: String,
        kind: String,
        sectionIndex: Int,
        range: NSRange,
        quote: String? = nil
    ) {
        self.id = id
        self.text = text
        self.quote = quote
        self.kind = kind
        self.sectionIndex = sectionIndex
        self.range = range
    }

    static func mergedHighlight(
        text: String,
        sectionIndex: Int,
        range: NSRange,
        into annotations: [ReaderAnnotation]
    ) -> [ReaderAnnotation] {
        guard range.length > 0 else { return annotations }
        var mergedRange = range
        var mergedText = text
        var mergedSegments: [(range: NSRange, text: String)] = [(range, text)]
        var result: [ReaderAnnotation] = []
        var merged = false
        for annotation in annotations {
            guard annotation.kind == "highlight", annotation.sectionIndex == sectionIndex else {
                result.append(annotation)
                continue
            }
            let end = max(NSMaxRange(mergedRange), NSMaxRange(annotation.range))
            let start = min(mergedRange.location, annotation.range.location)
            let touches = NSMaxRange(annotation.range) >= mergedRange.location &&
                annotation.range.location <= NSMaxRange(mergedRange)
            guard touches else {
                result.append(annotation)
                continue
            }
            mergedRange = NSRange(location: start, length: end - start)
            mergedSegments.append((annotation.range, annotation.text))
            merged = true
        }
        if merged {
            mergedSegments.sort { $0.range.location < $1.range.location }
            mergedText = mergedSegments.dropFirst().reduce(mergedSegments.first?.text ?? mergedText) { result, segment in
                let overlap = min(result.count, segment.text.count)
                var common = 0
                if overlap > 0 {
                    for length in stride(from: overlap, through: 1, by: -1) {
                        if result.suffix(length) == segment.text.prefix(length) {
                            common = length
                            break
                        }
                    }
                }
                return result + segment.text.dropFirst(common)
            }
        }
        result.insert(
            ReaderAnnotation(text: mergedText, kind: "highlight", sectionIndex: sectionIndex, range: mergedRange),
            at: 0
        )
        return result
    }
}

struct ReaderCommand: Equatable, Identifiable {
    let id = UUID()
    let action: ReaderAction
}
