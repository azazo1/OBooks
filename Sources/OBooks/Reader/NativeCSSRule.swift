import Foundation

struct NativeCSSFontFace {
    let family: String
    let sourceURL: URL
}

struct NativeCSSRule {
    let selector: NativeCSSSelector
    let declarations: [(property: String, value: String)]
    let order: Int

    var specificity: Int { selector.specificity }

    func matches(_ node: XMLNode, ancestors: [XMLNode]) -> Bool {
        selector.matches(node, ancestors: ancestors)
    }

    static func parse(styles: [String]) -> [NativeCSSRule] {
        var rules: [NativeCSSRule] = []
        var order = 0
        for style in styles {
            parseStylesheet(removeComments(from: style), order: &order, into: &rules)
        }
        return rules
    }

    static func parseFontFaces(styles: [(source: String, baseURL: URL)]) -> [NativeCSSFontFace] {
        var result: [NativeCSSFontFace] = []
        for entry in styles {
            let source = removeComments(from: entry.source)
            var cursor = source.startIndex
            while cursor < source.endIndex {
                guard let open = source[cursor...].firstIndex(of: "{") else { break }
                let header = source[cursor..<open].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let close = matchingBrace(in: source, after: open) else { break }
                let body = String(source[source.index(after: open)..<close])
                cursor = source.index(after: close)
                guard header == "@font-face" else { continue }
                let declarations = parseDeclarations(body)
                guard let family = declarations.first(where: { $0.property == "font-family" }).map({ cleanFamilyName($0.value) }),
                      !family.isEmpty,
                      let rawSource = declarations.first(where: { $0.property == "src" }).flatMap({ cssURL(in: $0.value) }),
                      let sourceURL = URL(string: rawSource.removingPercentEncoding ?? rawSource, relativeTo: entry.baseURL.deletingLastPathComponent())?.standardizedFileURL else { continue }
                result.append(NativeCSSFontFace(family: family, sourceURL: sourceURL))
            }
        }
        return result
    }

    private static func cleanFamilyName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func cssURL(in value: String) -> String? {
        guard let start = value.range(of: "url(", options: .caseInsensitive)?.upperBound,
              let end = value[start...].firstIndex(of: ")") else { return nil }
        return value[start..<end].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    static func parseDeclarations(_ source: String) -> [(property: String, value: String)] {
        split(source, separator: ";").compactMap { declaration in
            guard let colon = declaration.firstIndex(of: ":") else { return nil }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !property.isEmpty, !value.isEmpty else { return nil }
            return (property, value)
        }
    }

    private static func parseStylesheet(_ source: String, order: inout Int, into rules: inout [NativeCSSRule]) {
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard let open = source[cursor...].firstIndex(of: "{") else { return }
            let header = source[cursor..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let close = matchingBrace(in: source, after: open) else { return }
            let body = String(source[source.index(after: open)..<close])
            cursor = source.index(after: close)

            if header.hasPrefix("@media") || header.hasPrefix("@supports") || header.hasPrefix("@layer") {
                parseStylesheet(body, order: &order, into: &rules)
                continue
            }
            guard !header.isEmpty, !header.hasPrefix("@") else { continue }
            let declarations = parseDeclarations(body)
            guard !declarations.isEmpty else { continue }
            for selectorSource in split(header, separator: ",") {
                guard let selector = NativeCSSSelector.parse(selectorSource) else { continue }
                rules.append(NativeCSSRule(selector: selector, declarations: declarations, order: order))
            }
            order += 1
        }
    }

    private static func matchingBrace(in source: String, after open: String.Index) -> String.Index? {
        var depth = 1
        var quote: Character?
        var escaped = false
        var index = source.index(after: open)
        while index < source.endIndex {
            let character = source[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func split(_ source: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var parenthesisDepth = 0
        var bracketDepth = 0
        for character in source {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                continue
            }
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "(" {
                parenthesisDepth += 1
                current.append(character)
            } else if character == ")" {
                parenthesisDepth = max(0, parenthesisDepth - 1)
                current.append(character)
            } else if character == "[" {
                bracketDepth += 1
                current.append(character)
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            } else if character == separator, parenthesisDepth == 0, bracketDepth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.filter { !$0.isEmpty }
    }

    private static func removeComments(from source: String) -> String {
        var result = ""
        var index = source.startIndex
        while index < source.endIndex {
            let next = source.index(after: index)
            if source[index] == "/", next < source.endIndex, source[next] == "*" {
                guard let end = source[next...].range(of: "*/")?.upperBound else { return result }
                index = end
            } else {
                result.append(source[index])
                index = next
            }
        }
        return result
    }
}

struct NativeCSSSelector {
    enum Relation {
        case descendant
        case child
    }

    struct AttributeMatcher {
        enum Operation {
            case exists
            case equals
            case containsWord
            case startsWith
            case endsWith
            case contains
        }

        let name: String
        let operation: Operation
        let value: String?

        func matches(_ node: XMLNode) -> Bool {
            guard let attribute = node.attribute(name) else { return false }
            guard let value else { return true }
            switch operation {
            case .exists:
                return true
            case .equals:
                return attribute.caseInsensitiveCompare(value) == .orderedSame
            case .containsWord:
                return attribute.split(whereSeparator: { $0.isWhitespace }).contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            case .startsWith:
                return attribute.lowercased().hasPrefix(value.lowercased())
            case .endsWith:
                return attribute.lowercased().hasSuffix(value.lowercased())
            case .contains:
                return attribute.range(of: value, options: .caseInsensitive) != nil
            }
        }
    }

    struct Compound {
        var tag: String?
        var id: String?
        var classes: [String] = []
        var attributes: [AttributeMatcher] = []
        var specificity = 0

        func matches(_ node: XMLNode) -> Bool {
            if let tag, tag != "*", node.name != tag { return false }
            if let id, node.attribute("id") != id { return false }
            if !classes.isEmpty {
                let nodeClasses = Set((node.attribute("class") ?? "").split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() })
                guard classes.allSatisfy({ nodeClasses.contains($0.lowercased()) }) else { return false }
            }
            return attributes.allSatisfy { $0.matches(node) }
        }
    }

    struct Part {
        let compound: Compound
        let relationToPrevious: Relation?
    }

    let parts: [Part]
    let specificity: Int

    static func parse(_ source: String) -> NativeCSSSelector? {
        let tokens = tokenize(source)
        guard !tokens.isEmpty else { return nil }
        var parts: [Part] = []
        for token in tokens {
            guard let compound = parseCompound(token.value) else { return nil }
            parts.append(Part(compound: compound, relationToPrevious: parts.isEmpty ? nil : token.relation))
        }
        return NativeCSSSelector(parts: parts, specificity: parts.reduce(0) { $0 + $1.compound.specificity })
    }

    func matches(_ node: XMLNode, ancestors: [XMLNode]) -> Bool {
        match(partIndex: parts.count - 1, node: node, ancestors: ancestors)
    }

    private func match(partIndex: Int, node: XMLNode, ancestors: [XMLNode]) -> Bool {
        guard parts[partIndex].compound.matches(node) else { return false }
        guard partIndex > 0 else { return true }
        switch parts[partIndex].relationToPrevious ?? .descendant {
        case .child:
            guard let parent = ancestors.last else { return false }
            return match(partIndex: partIndex - 1, node: parent, ancestors: Array(ancestors.dropLast()))
        case .descendant:
            for ancestorIndex in ancestors.indices.reversed() {
                if match(
                    partIndex: partIndex - 1,
                    node: ancestors[ancestorIndex],
                    ancestors: Array(ancestors[..<ancestorIndex])
                ) {
                    return true
                }
            }
            return false
        }
    }

    private static func tokenize(_ source: String) -> [(value: String, relation: Relation?)] {
        var result: [(String, Relation?)] = []
        var current = ""
        var quote: Character?
        var bracketDepth = 0
        var pendingRelation: Relation?

        func flush() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            result.append((value, result.isEmpty ? nil : pendingRelation ?? .descendant))
            current = ""
            pendingRelation = nil
        }

        for character in source.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "[" {
                bracketDepth += 1
                current.append(character)
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            } else if bracketDepth == 0, character == ">" {
                flush()
                pendingRelation = .child
            } else if bracketDepth == 0, character.isWhitespace {
                flush()
            } else if bracketDepth == 0, character == "+" || character == "~" {
                return []
            } else {
                current.append(character)
            }
        }
        flush()
        return result
    }

    private static func parseCompound(_ source: String) -> Compound? {
        var compound = Compound()
        let characters = Array(source)
        var index = 0

        if index < characters.count, characters[index] == "*" {
            compound.tag = "*"
            index += 1
        } else if index < characters.count, isIdentifierCharacter(characters[index]) {
            let value = readIdentifier(characters, index: &index)
            compound.tag = value.split(separator: "|").last.map { String($0).lowercased() }
            compound.specificity += 1
        }

        while index < characters.count {
            switch characters[index] {
            case ".":
                index += 1
                let value = readIdentifier(characters, index: &index)
                guard !value.isEmpty else { return nil }
                compound.classes.append(value)
                compound.specificity += 10
            case "#":
                index += 1
                let value = readIdentifier(characters, index: &index)
                guard !value.isEmpty else { return nil }
                compound.id = value
                compound.specificity += 100
            case "[":
                guard let close = characters[(index + 1)...].firstIndex(of: "]") else { return nil }
                let expression = String(characters[(index + 1)..<close])
                guard let matcher = parseAttribute(expression) else { return nil }
                compound.attributes.append(matcher)
                compound.specificity += 10
                index = close + 1
            case ":":
                return nil
            default:
                return nil
            }
        }
        return compound
    }

    private static func parseAttribute(_ source: String) -> AttributeMatcher? {
        let operators: [(String, AttributeMatcher.Operation)] = [
            ("~=", .containsWord), ("^=", .startsWith), ("$=", .endsWith), ("*=", .contains), ("=", .equals)
        ]
        for (symbol, operation) in operators {
            if let range = source.range(of: symbol) {
                let name = normalizeAttributeName(String(source[..<range.lowerBound]))
                var value = source[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 2, (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
                    value.removeFirst()
                    value.removeLast()
                }
                guard !name.isEmpty, !value.isEmpty else { return nil }
                return AttributeMatcher(name: name, operation: operation, value: value)
            }
        }
        let name = normalizeAttributeName(source)
        guard !name.isEmpty else { return nil }
        return AttributeMatcher(name: name, operation: .exists, value: nil)
    }

    private static func normalizeAttributeName(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "|", with: ":").lowercased()
    }

    private static func readIdentifier(_ characters: [Character], index: inout Int) -> String {
        let start = index
        while index < characters.count, isIdentifierCharacter(characters[index]) {
            index += 1
        }
        return String(characters[start..<index])
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == "|"
    }
}
