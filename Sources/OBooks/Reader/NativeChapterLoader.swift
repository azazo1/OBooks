import AppKit
import CoreText
import Foundation

struct NativeChapterDocument {
    let attributedText: NSAttributedString
    let anchors: [String: Int]
}

struct NativeChapterLoader {
    func load(book: BookSummary, sectionIndex: Int, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor) throws -> NSAttributedString {
        try loadDocument(
            book: book,
            sectionIndex: sectionIndex,
            fontSize: fontSize,
            lineHeight: lineHeight,
            foreground: foreground
        ).attributedText
    }

    func loadDocument(book: BookSummary, sectionIndex: Int, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor) throws -> NativeChapterDocument {
        guard book.spine.indices.contains(sectionIndex) else {
            throw EPUBImportError.invalidPackage("章节索引无效")
        }
        let chapterURL = book.folderURL.appendingPathComponent(book.spine[sectionIndex].href).standardizedFileURL
        let rootURL = book.folderURL.standardizedFileURL
        guard chapterURL.path.hasPrefix(rootURL.path + "/"), FileManager.default.fileExists(atPath: chapterURL.path) else {
            throw EPUBImportError.invalidPackage("找不到章节文件")
        }
        let data = try Data(contentsOf: chapterURL)
        return try loadDocument(
            data: data,
            chapterURL: chapterURL,
            rootURL: rootURL,
            fontSize: fontSize,
            lineHeight: lineHeight,
            foreground: foreground
        )
    }

    func load(data: Data, chapterURL: URL, rootURL: URL, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor) throws -> NSAttributedString {
        try loadDocument(
            data: data,
            chapterURL: chapterURL,
            rootURL: rootURL,
            fontSize: fontSize,
            lineHeight: lineHeight,
            foreground: foreground
        ).attributedText
    }

    func loadDocument(data: Data, chapterURL: URL, rootURL: URL, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor) throws -> NativeChapterDocument {
        let root = try XMLTreeParser().parse(data)
        let body = root.first(named: "body") ?? root
        var styleSources: [(source: String, baseURL: URL)] = root.all(named: "style").map {
            (source: $0.textContent, baseURL: chapterURL)
        }
        for link in root.all(named: "link") {
            guard link.attribute("rel")?.lowercased().split(whereSeparator: { $0.isWhitespace }).contains("stylesheet") == true,
                  let href = link.attribute("href"),
                  let cssURL = URL(string: href.removingPercentEncoding ?? href, relativeTo: chapterURL.deletingLastPathComponent())?.standardizedFileURL,
                  cssURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/"),
                  let cssData = try? Data(contentsOf: cssURL),
                  let css = String(data: cssData, encoding: .utf8) else { continue }
            styleSources.append((source: css, baseURL: cssURL))
        }
        let fontNames = registerFonts(
            NativeCSSRule.parseFontFaces(styles: styleSources),
            rootURL: rootURL.standardizedFileURL
        )
        let rules = NativeCSSRule.parse(styles: styleSources.map(\.source))
        let builder = Builder(
            rootURL: rootURL,
            chapterURL: chapterURL,
            fontSize: fontSize,
            lineHeight: lineHeight,
            foreground: foreground,
            rules: rules,
            fontNames: fontNames
        )
        builder.render(body, style: Builder.Style(font: NSFont.systemFont(ofSize: fontSize)))
        return NativeChapterDocument(attributedText: builder.result, anchors: builder.anchors)
    }

    private func registerFonts(_ faces: [NativeCSSFontFace], rootURL: URL) -> [String: String] {
        var result: [String: String] = [:]
        for face in faces {
            guard face.sourceURL.isFileURL,
                  face.sourceURL.path.hasPrefix(rootURL.path + "/"),
                  FileManager.default.fileExists(atPath: face.sourceURL.path) else { continue }
            var registrationError: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(face.sourceURL as CFURL, .process, &registrationError)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(face.sourceURL as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first,
                  let fontName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { continue }
            result[face.family.lowercased()] = fontName
        }
        return result
    }

    private final class Builder {
        let rootURL: URL
        let chapterURL: URL
        let fontSize: CGFloat
        let lineHeight: CGFloat
        let foreground: NSColor
        let rules: [NativeCSSRule]
        let fontNames: [String: String]
        let result = NSMutableAttributedString(string: "")
        var anchors: [String: Int] = [:]
        var ancestorStack: [XMLNode] = []
        var listDepth = 0

        init(rootURL: URL, chapterURL: URL, fontSize: CGFloat, lineHeight: CGFloat, foreground: NSColor, rules: [NativeCSSRule], fontNames: [String: String]) {
            self.rootURL = rootURL.standardizedFileURL
            self.chapterURL = chapterURL
            self.fontSize = fontSize
            self.lineHeight = lineHeight
            self.foreground = foreground
            self.rules = rules
            self.fontNames = fontNames
        }

        func render(_ node: XMLNode, style: Style) {
            switch node.name {
            case "head", "script", "style", "title", "meta", "link", "noscript", "rt":
                return
            case "br":
                append("\n", style)
                return
            case "hr":
                append("\n--------\n", style)
                return
            case "img", "image":
                appendImage(node, style: style)
                return
            default:
                break
            }

            var nextStyle = style
            nextStyle.displayBlock = false
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
            } else if node.name == "center" {
                nextStyle.alignment = .center
            } else if node.name == "sup" {
                nextStyle.baselineOffset = fontSize * 0.35
                nextStyle.font = resizedFont(nextStyle.font, to: fontSize * 0.72)
            } else if node.name == "sub" {
                nextStyle.baselineOffset = -fontSize * 0.2
                nextStyle.font = resizedFont(nextStyle.font, to: fontSize * 0.72)
            } else if node.name == "small" {
                nextStyle.font = resizedFont(nextStyle.font, to: nextStyle.font.pointSize * 0.82)
            } else if node.name == "del" || node.name == "s" || node.name == "strike" {
                nextStyle.strikethrough = true
            } else if node.name == "mark" {
                nextStyle.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.35)
            } else if node.name == "a", let href = node.attribute("href") {
                nextStyle.link = URL(string: href, relativeTo: chapterURL)?.absoluteURL
                nextStyle.underline = true
            }

            applyCSS(to: &nextStyle, node: node)
            guard !nextStyle.hidden else { return }

            let block = Self.blockTags.contains(node.name) || nextStyle.displayBlock
            if node.name == "ul" || node.name == "ol" {
                listDepth += 1
            }
            if node.name == "li" {
                ensureBlockBreak(style: nextStyle)
                let marker = node.attribute("class")?.lowercased().contains("none") == true ? "" : "- "
                append(String(repeating: "  ", count: max(0, listDepth - 1)) + marker, nextStyle)
            }

            if block {
                ensureBlockBreak(style: nextStyle)
            }
            registerAnchors(for: node)

            ancestorStack.append(node)
            for content in node.orderedContent {
                switch content {
                case .text(let text):
                    append(normalize(text, preformatted: nextStyle.preformatted), nextStyle)
                case .element(let child):
                    render(child, style: nextStyle)
                }
            }
            _ = ancestorStack.popLast()

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
            let lineHeightMultiple = style.lineHeightMultiple ?? lineHeight
            paragraph.lineHeightMultiple = lineHeightMultiple
            paragraph.minimumLineHeight = style.font.pointSize * lineHeightMultiple * 0.82
            paragraph.maximumLineHeight = style.font.pointSize * lineHeightMultiple * 1.35
            paragraph.paragraphSpacing = style.paragraphSpacing
            paragraph.paragraphSpacingBefore = style.paragraphSpacingBefore
            paragraph.firstLineHeadIndent = style.firstLineHeadIndent
            paragraph.headIndent = style.headIndent
            paragraph.tailIndent = style.tailIndent
            paragraph.alignment = style.alignment
            var attributes: [NSAttributedString.Key: Any] = [
                .font: style.font,
                .foregroundColor: style.textColor ?? foreground,
                .paragraphStyle: paragraph
            ]
            if style.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if style.strikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if style.baselineOffset != 0 {
                attributes[.baselineOffset] = style.baselineOffset
            }
            if let shadow = style.shadow {
                attributes[.shadow] = shadow
            }
            if let backgroundColor = style.backgroundColor {
                attributes[.backgroundColor] = backgroundColor
            }
            if style.link != nil {
                attributes[.link] = style.link as Any
                if style.textColor == nil {
                    attributes[.foregroundColor] = NSColor.systemBlue
                }
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }

        private func appendImage(_ node: XMLNode, style: Style) {
            guard let source = node.attribute("src") ?? node.attribute("href") else { return }
            let path = source.split(separator: "#", maxSplits: 1).first.map(String.init) ?? source
            guard let imageURL = URL(string: path.removingPercentEncoding ?? path, relativeTo: chapterURL.deletingLastPathComponent())?.standardizedFileURL,
                  imageURL.path.hasPrefix(rootURL.path + "/"),
                  let image = NSImage(contentsOf: imageURL) else { return }
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = image.size
            if size.width > 0, size.height > 0 {
                let width = min(size.width, 600)
                attachment.bounds = NSRect(x: 0, y: 0, width: width, height: width * size.height / size.width)
            }
            let imageText = NSMutableAttributedString(attachment: attachment)
            let imageParagraph = paragraphStyle(for: style)
            imageParagraph.lineHeightMultiple = 0
            imageParagraph.minimumLineHeight = 0
            imageParagraph.maximumLineHeight = 0
            imageText.addAttribute(.paragraphStyle, value: imageParagraph, range: NSRange(location: 0, length: imageText.length))
            result.append(imageText)
            append("\n\n", style)
        }

        private func paragraphStyle(for style: Style) -> NSMutableParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            let lineHeightMultiple = style.lineHeightMultiple ?? lineHeight
            paragraph.lineHeightMultiple = lineHeightMultiple
            paragraph.minimumLineHeight = style.font.pointSize * lineHeightMultiple * 0.82
            paragraph.maximumLineHeight = style.font.pointSize * lineHeightMultiple * 1.35
            paragraph.alignment = style.alignment
            paragraph.paragraphSpacing = style.paragraphSpacing
            paragraph.paragraphSpacingBefore = style.paragraphSpacingBefore
            paragraph.firstLineHeadIndent = style.firstLineHeadIndent
            paragraph.headIndent = style.headIndent
            paragraph.tailIndent = style.tailIndent
            return paragraph
        }

        private func applyCSS(to style: inout Style, node: XMLNode) {
            let matchingRules = rules
                .filter { $0.matches(node, ancestors: ancestorStack) }
                .sorted {
                    if $0.specificity == $1.specificity { return $0.order < $1.order }
                    return $0.specificity < $1.specificity
                }
            for rule in matchingRules {
                for declaration in rule.declarations {
                    apply(property: declaration.property, value: declaration.value, to: &style)
                }
            }
            if let inlineStyle = node.attribute("style") {
                for declaration in NativeCSSRule.parseDeclarations(inlineStyle) {
                    apply(property: declaration.property, value: declaration.value, to: &style)
                }
            }
            if node.attribute("hidden") != nil {
                style.hidden = true
            }
        }

        private func apply(property: String, value: String, to style: inout Style) {
            let property = property.lowercased()
            let value = value.lowercased()
                .replacingOccurrences(of: "!important", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            switch property {
            case "display":
                style.hidden = value == "none"
                style.displayBlock = ["block", "list-item", "table", "table-row", "table-cell"].contains(value)
            case "visibility":
                style.hidden = value == "hidden" || value == "collapse"
            case "font-size":
                if let size = cssLength(value, relativeTo: fontSize, allowPercent: true) {
                    style.font = resizedFont(style.font, to: size)
                }
            case "font-weight":
                if value == "bold" || value == "bolder" || (Int(value).map { $0 >= 600 } ?? false) {
                    style.font = NSFontManager.shared.convert(style.font, toHaveTrait: .boldFontMask)
                } else if value == "normal" || value == "400" {
                    style.font = NSFontManager.shared.convert(style.font, toNotHaveTrait: .boldFontMask)
                }
            case "font-style":
                if value == "italic" || value == "oblique" {
                    style.font = NSFontManager.shared.convert(style.font, toHaveTrait: .italicFontMask)
                } else if value == "normal" {
                    style.font = NSFontManager.shared.convert(style.font, toNotHaveTrait: .italicFontMask)
                }
            case "font-family":
                let family = value.split(separator: ",").first.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                } ?? ""
                if family == "monospace" || family == "monaco" || family == "menlo" {
                    style.font = NSFont.monospacedSystemFont(ofSize: style.font.pointSize, weight: .regular)
                } else if let font = NSFont(name: fontNames[family.lowercased()] ?? family, size: style.font.pointSize) {
                    style.font = font
                }
            case "text-align":
                switch value {
                case "left", "start": style.alignment = .left
                case "right", "end": style.alignment = .right
                case "center": style.alignment = .center
                case "justify": style.alignment = .justified
                default: break
                }
            case "text-indent":
                if let indent = cssLength(value, relativeTo: fontSize, allowPercent: true) {
                    style.firstLineHeadIndent = indent
                }
            case "margin-top", "padding-top":
                if let spacing = cssLength(value, relativeTo: fontSize, allowPercent: false) {
                    style.paragraphSpacingBefore = spacing
                }
            case "margin-bottom", "padding-bottom":
                if let spacing = cssLength(value, relativeTo: fontSize, allowPercent: false) {
                    style.paragraphSpacing = spacing
                }
            case "margin", "padding":
                let values = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if let first = values.first.flatMap({ cssLength($0, relativeTo: fontSize, allowPercent: false) }) {
                    style.paragraphSpacingBefore = first
                    style.paragraphSpacing = first
                }
                if values.count >= 2, let horizontal = cssLength(values[1], relativeTo: fontSize, allowPercent: false) {
                    style.headIndent = max(style.headIndent, horizontal)
                }
                if values.count >= 3, let bottom = cssLength(values[2], relativeTo: fontSize, allowPercent: false) {
                    style.paragraphSpacing = bottom
                }
            case "padding-left", "margin-left":
                if let inset = cssLength(value, relativeTo: fontSize, allowPercent: false) {
                    style.headIndent = inset
                }
            case "padding-right", "margin-right":
                if let inset = cssLength(value, relativeTo: fontSize, allowPercent: false) {
                    style.tailIndent = -inset
                }
            case "line-height":
                if let multiple = Double(value), multiple > 0 {
                    style.lineHeightMultiple = CGFloat(multiple)
                } else if let height = cssLength(value, relativeTo: style.font.pointSize, allowPercent: true) {
                    style.lineHeightMultiple = height / style.font.pointSize
                }
            case "text-decoration":
                style.underline = value.contains("underline")
                style.strikethrough = value.contains("line-through")
            case "color":
                style.textColor = color(for: value)
            case "background-color":
                style.backgroundColor = color(for: value)
            case "text-shadow":
                style.shadow = textShadow(for: value)
            case "white-space":
                style.preformatted = value == "pre" || value == "pre-wrap"
            case "vertical-align":
                if value == "super" { style.baselineOffset = fontSize * 0.35 }
                if value == "sub" { style.baselineOffset = -fontSize * 0.2 }
            default:
                break
            }
        }

        private func registerAnchors(for node: XMLNode) {
            for key in [node.attribute("id"), node.attribute("name")].compactMap({ $0 }) where !key.isEmpty {
                anchors[key.removingPercentEncoding ?? key] = result.length
            }
        }

        private func cssLength(_ value: String, relativeTo base: CGFloat, allowPercent: Bool) -> CGFloat? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "0" { return 0 }
            if trimmed.hasSuffix("px") { return CGFloat(Double(trimmed.dropLast(2)) ?? 0) }
            if trimmed.hasSuffix("pt") { return CGFloat(Double(trimmed.dropLast(2)) ?? 0) }
            if trimmed.hasSuffix("em") { return base * CGFloat(Double(trimmed.dropLast(2)) ?? 0) }
            if trimmed.hasSuffix("rem") { return fontSize * CGFloat(Double(trimmed.dropLast(3)) ?? 0) }
            if allowPercent, trimmed.hasSuffix("%") {
                return base * CGFloat(Double(trimmed.dropLast()) ?? 0) / 100
            }
            return Double(trimmed).map { CGFloat($0) }
        }

        private func resizedFont(_ font: NSFont, to size: CGFloat) -> NSFont {
            NSFont(descriptor: font.fontDescriptor, size: max(8, size)) ?? NSFont.systemFont(ofSize: max(8, size))
        }

        private func textShadow(for value: String) -> NSShadow? {
            let tokens = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 2, value != "none" else { return nil }
            let lengths = tokens.prefix(3).compactMap { cssLength($0, relativeTo: fontSize, allowPercent: false) }
            guard lengths.count >= 2 else { return nil }
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: lengths[0], height: -lengths[1])
            shadow.shadowBlurRadius = lengths.count > 2 ? lengths[2] : 0
            if let colorToken = tokens.last, let color = color(for: colorToken) {
                shadow.shadowColor = color
            } else {
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            }
            return shadow
        }

        private func color(for value: String) -> NSColor? {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("#") {
                let hex = String(value.dropFirst())
                let digits = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
                guard let number = UInt64(digits, radix: 16) else { return nil }
                let divisor: CGFloat = 255
                return NSColor(
                    calibratedRed: CGFloat((number >> 16) & 0xff) / divisor,
                    green: CGFloat((number >> 8) & 0xff) / divisor,
                    blue: CGFloat(number & 0xff) / divisor,
                    alpha: 1
                )
            }
            switch value {
            case "black": return .black
            case "white": return .white
            case "red": return .red
            case "green": return .green
            case "blue": return .blue
            case "gray", "grey": return .gray
            case "yellow": return .yellow
            default: return nil
            }
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
            var strikethrough = false
            var hidden = false
            var displayBlock = false
            var alignment: NSTextAlignment = .natural
            var baselineOffset: CGFloat = 0
            var lineHeightMultiple: CGFloat?
            var textColor: NSColor?
            var backgroundColor: NSColor?
            var shadow: NSShadow?
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
