import Foundation

struct ReaderSearchHit: Identifiable, Equatable {
    var id: String { "\(sectionIndex)-\(occurrenceIndex)" }
    let query: String
    let sectionIndex: Int
    let spineID: String
    let chapterTitle: String
    let snippet: String
    let matchRangeInSnippet: NSRange
    let occurrenceIndex: Int
    let characterOffset: Int
}

struct ReaderSearchReveal: Equatable {
    let id: UUID
    let query: String
    let spineID: String
    let occurrenceIndex: Int

    init(query: String, spineID: String, occurrenceIndex: Int) {
        self.id = UUID()
        self.query = query
        self.spineID = spineID
        self.occurrenceIndex = occurrenceIndex
    }
}

enum ReaderSearchIndex {
    static let maxHits = 80
    static let maxHitsPerChapter = 8

    static func hits(
        in text: String,
        query: String,
        sectionIndex: Int,
        spineID: String,
        title: String
    ) -> [ReaderSearchHit] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !text.isEmpty else { return [] }
        let source = text as NSString
        var hits: [ReaderSearchHit] = []
        var searchRange = NSRange(location: 0, length: source.length)
        var occurrence = 0
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        while hits.count < maxHitsPerChapter {
            let found = source.range(of: trimmedQuery, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            let snippet = makeSnippet(in: source, match: found)
            hits.append(
                ReaderSearchHit(
                    query: trimmedQuery,
                    sectionIndex: sectionIndex,
                    spineID: spineID,
                    chapterTitle: title,
                    snippet: snippet.text,
                    matchRangeInSnippet: snippet.matchRange,
                    occurrenceIndex: occurrence,
                    characterOffset: found.location
                )
            )
            occurrence += 1
            let next = NSMaxRange(found)
            guard next < source.length else { break }
            searchRange = NSRange(location: next, length: source.length - next)
        }
        return hits
    }

    static func chapterTitle(book: BookSummary, tocIndex: ReaderTOCIndex, sectionIndex: Int) -> String {
        guard book.spine.indices.contains(sectionIndex) else {
            return "第 \(sectionIndex + 1) 章"
        }
        if let labeled = tocIndex.entries.first(where: { $0.sectionIndex == sectionIndex }) {
            return labeled.item.label
        }
        let spineTitle = book.spine[sectionIndex].title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spineTitle.isEmpty {
            return spineTitle
        }
        if let preceding = tocIndex.entries.last(where: { ($0.sectionIndex ?? Int.max) <= sectionIndex }) {
            return preceding.item.label
        }
        return "第 \(sectionIndex + 1) 章"
    }

    private static func makeSnippet(in source: NSString, match: NSRange) -> (text: String, matchRange: NSRange) {
        let full = source as String
        guard let matchRange = Range(match, in: full) else {
            return (source.substring(with: match), NSRange(location: 0, length: match.length))
        }
        let prefixStart = full.index(matchRange.lowerBound, offsetBy: -36, limitedBy: full.startIndex) ?? full.startIndex
        let suffixEnd = full.index(matchRange.upperBound, offsetBy: 36, limitedBy: full.endIndex) ?? full.endIndex
        let prefix = String(full[prefixStart..<matchRange.lowerBound]).replacingOccurrences(of: "\n", with: " ")
        let matchText = String(full[matchRange]).replacingOccurrences(of: "\n", with: " ")
        let suffix = String(full[matchRange.upperBound..<suffixEnd]).replacingOccurrences(of: "\n", with: " ")
        let leadingEllipsis = prefixStart != full.startIndex
        let trailingEllipsis = suffixEnd != full.endIndex
        var snippet = prefix + matchText + suffix
        if leadingEllipsis {
            snippet = "..." + snippet
        }
        if trailingEllipsis {
            snippet += "..."
        }
        let location = (leadingEllipsis ? 3 : 0) + (prefix as NSString).length
        return (snippet, NSRange(location: location, length: (matchText as NSString).length))
    }
}
