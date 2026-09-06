import Foundation

struct ReaderSearchTextExtractor {
    func extract(book: BookSummary, sectionIndex: Int) throws -> String {
        guard book.spine.indices.contains(sectionIndex) else {
            throw EPUBImportError.invalidPackage("章节索引无效")
        }
        let chapterURL = book.folderURL.appendingPathComponent(book.spine[sectionIndex].href).standardizedFileURL
        let rootURL = book.folderURL.standardizedFileURL
        guard chapterURL.path.hasPrefix(rootURL.path + "/"),
              FileManager.default.fileExists(atPath: chapterURL.path)
        else {
            throw EPUBImportError.invalidPackage("找不到章节文件")
        }
        return try extract(data: try Data(contentsOf: chapterURL))
    }

    func extract(data: Data) throws -> String {
        let root = try XMLTreeParser().parse(data)
        let body = root.first(named: "body") ?? root
        var result = ""
        render(body, into: &result, preformatted: false)
        return result
    }

    private func render(_ node: XMLNode, into result: inout String, preformatted: Bool) {
        if Self.skippedTags.contains(node.name) {
            return
        }
        switch node.name {
        case "br":
            append("\n", into: &result)
            return
        case "hr":
            ensureBlockBreak(into: &result)
            return
        case "img", "image":
            return
        default:
            break
        }

        let nextPreformatted = preformatted || node.name == "pre" || node.name == "code"
        let block = Self.blockTags.contains(node.name)
        if block {
            ensureBlockBreak(into: &result)
        }
        for content in node.orderedContent {
            switch content {
            case .text(let text):
                append(normalize(text, preformatted: nextPreformatted), into: &result)
            case .element(let child):
                render(child, into: &result, preformatted: nextPreformatted)
            }
        }
        if block {
            ensureBlockBreak(into: &result)
        }
    }

    private func append(_ text: String, into result: inout String) {
        guard !text.isEmpty else { return }
        result.append(text)
    }

    private func ensureBlockBreak(into result: inout String) {
        guard !result.isEmpty, !result.hasSuffix("\n") else { return }
        result.append("\n")
    }

    private func normalize(_ text: String, preformatted: Bool) -> String {
        if preformatted {
            return text.replacingOccurrences(of: "\r", with: "")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let hasLeadingSpace = text.first?.isWhitespace == true
        let hasTrailingSpace = text.last?.isWhitespace == true
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }
        return (hasLeadingSpace ? " " : "") + collapsed + (hasTrailingSpace ? " " : "")
    }

    private static let skippedTags: Set<String> = [
        "head", "script", "style", "title", "meta", "link", "noscript", "rt", "rp"
    ]

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "aside", "nav",
        "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "figure", "figcaption",
        "ul", "ol", "li", "table", "tr", "td", "th", "address"
    ]
}
