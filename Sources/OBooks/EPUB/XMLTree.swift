import Foundation

final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased(); self.attributes = attributes
    }
    func attribute(_ name: String) -> String? {
        if let value = attributes[name] { return value }
        return attributes.first { key, _ in key.lowercased().hasSuffix(":" + name.lowercased()) }?.value
    }
    func first(named name: String) -> XMLNode? {
        if self.name == name.lowercased() { return self }
        for child in children { if let found = child.first(named: name) { return found } }
        return nil
    }
    func all(named name: String) -> [XMLNode] {
        var result: [XMLNode] = self.name == name.lowercased() ? [self] : []
        for child in children { result.append(contentsOf: child.all(named: name)) }
        return result
    }
    var textContent: String { text + children.map(\.textContent).joined() }
}

final class XMLTreeParser: NSObject, XMLParserDelegate {
    private(set) var root: XMLNode?
    private var stack: [XMLNode] = []

    func parse(_ data: Data) throws -> XMLNode {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root else {
            throw EPUBImportError.invalidPackage(parser.parserError?.localizedDescription ?? "XML 解析失败")
        }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XMLNode(name: qName ?? elementName, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
}
