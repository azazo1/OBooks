import AppKit
import Foundation

struct NativeChapterLoader {
    func load(book: BookSummary, sectionIndex: Int, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor) throws -> NSAttributedString {
        guard book.spine.indices.contains(sectionIndex) else {
            throw EPUBImportError.invalidPackage("章节索引无效")
        }
        let chapterURL = book.folderURL.appendingPathComponent(book.spine[sectionIndex].href).standardizedFileURL
        let rootURL = book.folderURL.standardizedFileURL
        guard chapterURL.path.hasPrefix(rootURL.path + "/"), FileManager.default.fileExists(atPath: chapterURL.path) else {
            throw EPUBImportError.invalidPackage("找不到章节文件")
        }
        let data = try Data(contentsOf: chapterURL)
        return try load(
            data: data,
            chapterURL: chapterURL,
            rootURL: rootURL,
            fontSize: fontSize,
            lineHeight: lineHeight,
            foreground: foreground
        )
    }

    func load(data: Data, chapterURL: URL, rootURL: URL, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor) throws -> NSAttributedString {
        let root = try XMLTreeParser().parse(data)
        let body = root.first(named: "body") ?? root
        let builder = Builder(rootURL: rootURL, chapterURL: chapterURL, fontSize: fontSize, lineHeight: lineHeight, foreground: foreground)
        builder.render(body, style: Builder.Style(font: NSFont.systemFont(ofSize: fontSize)))
        return builder.result
    }

    private final class Builder {
        let rootURL: URL
        let chapterURL: URL
        let fontSize: CGFloat
        let lineHeight: CGFloat
        let foreground: NSColor
        let result = NSMutableAttributedString(string: "")
        var listDepth = 0

        init(rootURL: URL, chapterURL: URL, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor) {
            self.rootURL = rootURL.standardizedFileURL
            self.chapterURL = chapterURL
            self.fontSize = fontSize
            self.lineHeight = lineHeight
            self.foreground = foreground
        }

        func render(_ node: XMLNode, style: Style) {
            switch node.name {
            case "head", "script", "style", "title", "meta", "link", "noscript":
                return
            case "br":
                append("\n", style)
                return
            case "hr":
                append("\n--------\n", style)
                return
            case "img", "image":
                appendImage(node)
                return
            default:
                break
            }

            let block = Self.blockTags.contains(node.name)
            var nextStyle = style
            if node.name == "p" {
                nextStyle.paragraphSpacing = fontSize * 0.7
            }
            if let level = Self.headingLevel[node.name] {
                nextStyle.font = NSFont.systemFont(ofSize: max(fontSize * (1.48 - CGFloat(level) * 0.08), fontSize + 2), weight: .bold)
                nextStyle.paragraphSpacingBefore = fontSize * 0.85
                nextStyle.paragraphSpacing = fontSize * 0.55
            } else if node.name == "strong" || node.name == "b" {
                nextStyle.font = NSFontManager.shared.convert(style.font, toHaveTrait: .boldFontMask)
            } else if node.name == "em" || node.name == "i" {
                nextStyle.font = NSFontManager.shared.convert(style.font, toHaveTrait: .italicFontMask)
            } else if node.name == "code" || node.name == "pre" {
                nextStyle.font = NSFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular)
                nextStyle.preformatted = true
            } else if node.name == "blockquote" {
                nextStyle.firstLineHeadIndent = fontSize * 1.25
                nextStyle.headIndent = fontSize * 1.25
                nextStyle.paragraphSpacing = fontSize * 0.7
            } else if node.name == "a", let href = node.attribute("href") {
                nextStyle.link = URL(string: href, relativeTo: chapterURL)
                nextStyle.underline = true
            }

            if node.name == "ul" || node.name == "ol" {
                listDepth += 1
            }
            if node.name == "li" {
                ensureBlockBreak(style: nextStyle)
                append(String(repeating: "  ", count: max(0, listDepth - 1)) + "- ", nextStyle)
            }

            if block {
                ensureBlockBreak(style: nextStyle)
            }

            for content in node.orderedContent {
                switch content {
                case .text(let text):
                    append(normalize(text, preformatted: nextStyle.preformatted), nextStyle)
                case .element(let child):
                    render(child, style: nextStyle)
                }
            }

            if node.name == "ul" || node.name == "ol" {
                listDepth = max(0, listDepth - 1)
            }
            if block {
                ensureBlockBreak(style: nextStyle)
            }
        }

        private func append(_ text: String, _ style: Style) {
            guard !text.isEmpty else { return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = lineHeight
            paragraph.minimumLineHeight = fontSize * lineHeight * 0.82
            paragraph.maximumLineHeight = fontSize * lineHeight * 1.35
            paragraph.paragraphSpacing = style.paragraphSpacing
            paragraph.paragraphSpacingBefore = style.paragraphSpacingBefore
            paragraph.firstLineHeadIndent = style.firstLineHeadIndent
            paragraph.headIndent = style.headIndent
            paragraph.tailIndent = style.tailIndent
            var attributes: [NSAttributedString.Key: Any] = [
                .font: style.font,
                .foregroundColor: foreground,
                .paragraphStyle: paragraph
            ]
            if style.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if style.link != nil {
                attributes[.link] = style.link as Any
                attributes[.foregroundColor] = NSColor.systemBlue
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }

        private func appendImage(_ node: XMLNode) {
            guard let source = node.attribute("src") ?? node.attribute("href") else { return }
            let path = source.split(separator: "#", maxSplits: 1).first.map(String.init) ?? source
            guard let imageURL = URL(string: path, relativeTo: chapterURL.deletingLastPathComponent())?.standardizedFileURL,
                  imageURL.path.hasPrefix(rootURL.path + "/"),
                  let image = NSImage(contentsOf: imageURL) else { return }
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = image.size
            if size.width > 0, size.height > 0 {
                let width = min(size.width, 600)
                attachment.bounds = NSRect(x: 0, y: 0, width: width, height: width * size.height / size.width)
            }
            result.append(NSAttributedString(attachment: attachment))
            append("\n\n", Style(font: NSFont.systemFont(ofSize: fontSize)))
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

        private func ensureBlockBreak(count: Int = 1, style: Style) {
            guard result.length > 0 else { return }
            let existing = result.string.reversed().prefix { $0 == "\n" }.count
            let needed = max(0, count - existing)
            if needed > 0 {
                append(String(repeating: "\n", count: needed), style)
            }
        }

        struct Style {
            var font: NSFont
            var paragraphSpacing: CGFloat = 0
            var paragraphSpacingBefore: CGFloat = 0
            var firstLineHeadIndent: CGFloat = 0
            var headIndent: CGFloat = 0
            var tailIndent: CGFloat = 0
            var preformatted = false
            var underline = false
            var link: URL?
        }

        private static let blockTags: Set<String> = [
            "p", "div", "section", "article", "header", "footer", "main", "aside", "nav",
            "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "figure", "figcaption",
            "ul", "ol", "li", "table", "tr", "td", "th", "address"
        ]

        private static let headingLevel: [String: Int] = [
            "h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6
        ]
    }
}
