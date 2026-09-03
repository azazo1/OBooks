import Foundation
import OSLog

struct EPUBParser {
    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: String
    }

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.obooks.app", category: "epub.parser")

    func parse(folderURL: URL) throws -> EPUBPackageInfo {
        let encryptionURL = folderURL.appendingPathComponent("META-INF/encryption.xml")
        guard !fileManager.fileExists(atPath: encryptionURL.path) else { throw EPUBImportError.encryptedPublication }
        let containerURL = folderURL.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL) else { throw EPUBImportError.missingContainer }
        let containerRoot = try XMLTreeParser().parse(containerData)
        guard let rootFile = containerRoot.all(named: "rootfile").first?.attribute("full-path") else { throw EPUBImportError.missingPackage }
        let opfURL = try safeURL(rootFile, relativeTo: folderURL, rootURL: folderURL)
        guard let opfData = try? Data(contentsOf: opfURL) else { throw EPUBImportError.missingPackage }
        let opfRoot = try XMLTreeParser().parse(opfData)
        let packageNode = opfRoot.first(named: "package") ?? opfRoot
        let metadataNode = packageNode.first(named: "metadata")
        let title = cleanText(metadataNode?.all(named: "title").first?.textContent) ?? "未命名书籍"
        let authors = metadataNode?.all(named: "creator").compactMap { cleanText($0.textContent) } ?? []
        let manifestItems = parseManifest(packageNode.first(named: "manifest"), opfURL: opfURL, rootURL: folderURL)
        let manifestByID = Dictionary(uniqueKeysWithValues: manifestItems.map { ($0.id, $0) })
        guard let spineNode = packageNode.first(named: "spine") else { throw EPUBImportError.invalidPackage("缺少 spine") }
        var spine = spineNode.children.filter { $0.name == "itemref" }.compactMap { itemref -> EPUBSpineItem? in
            guard let idref = itemref.attribute("idref"), let item = manifestByID[idref] else { return nil }
            return EPUBSpineItem(id: item.id, href: item.href, title: item.href, linear: itemref.attribute("linear")?.lowercased() != "no")
        }
        guard !spine.isEmpty else { throw EPUBImportError.invalidPackage("spine 没有可阅读章节") }
        var toc: [EPUBTOCItem] = []
        if let navItem = manifestItems.first(where: { $0.properties.split(separator: " ").contains("nav") }) {
            let navURL = folderURL.appendingPathComponent(navItem.href).standardizedFileURL
            toc = parseNav(at: navURL, rootURL: folderURL)
        }
        if toc.isEmpty, let ncxID = spineNode.attribute("toc"), let ncxItem = manifestByID[ncxID] {
            let ncxURL = folderURL.appendingPathComponent(ncxItem.href).standardizedFileURL
            toc = parseNCX(at: ncxURL, rootURL: folderURL)
        }
        let coverPath = coverPath(metadata: metadataNode, manifest: manifestItems)
        spine = spine.map { item in
            EPUBSpineItem(id: item.id, href: item.href, title: tocTitle(for: item.href, in: toc) ?? item.title, linear: item.linear)
        }
        let readableSpine = spine.filter { $0.linear }
        let finalSpine = readableSpine.isEmpty ? spine : readableSpine
        logger.info("解析 EPUB: title=\(title, privacy: .public), chapters=\(finalSpine.count)")
        return EPUBPackageInfo(title: title, authors: authors, spine: finalSpine, toc: toc, coverPath: coverPath)
    }

    private func parseManifest(_ node: XMLNode?, opfURL: URL, rootURL: URL) -> [ManifestItem] {
        node?.children.filter { $0.name == "item" }.compactMap { item in
            guard let id = item.attribute("id"), let href = item.attribute("href"), let mediaType = item.attribute("media-type") else { return nil }
            guard let path = try? safeRelativePath(href, relativeTo: opfURL.deletingLastPathComponent(), rootURL: rootURL) else { return nil }
            return ManifestItem(id: id, href: path, mediaType: mediaType, properties: item.attribute("properties") ?? "")
        } ?? []
    }

    private func parseNav(at url: URL, rootURL: URL) -> [EPUBTOCItem] {
        guard let data = try? Data(contentsOf: url), let root = try? XMLTreeParser().parse(data) else { return [] }
        let nav = root.all(named: "nav").first(where: { ($0.attribute("type") ?? $0.attribute("epub:type") ?? "").contains("toc") }) ?? root.all(named: "nav").first
        return parseNavList(nav?.all(named: "ol").first, baseURL: url.deletingLastPathComponent(), rootURL: rootURL)
    }

    private func parseNavList(_ node: XMLNode?, baseURL: URL, rootURL: URL) -> [EPUBTOCItem] {
        guard let node else { return [] }
        return node.children.filter { $0.name == "li" }.compactMap { item in
            guard let anchor = item.children.first(where: { $0.name == "a" }), let href = anchor.attribute("href"),
                  let target = try? safeRelativePath(href, relativeTo: baseURL, rootURL: rootURL) else { return nil }
            let nested = item.children.first(where: { $0.name == "ol" })
            return EPUBTOCItem(label: cleanText(anchor.textContent) ?? "未命名章节", href: target, children: parseNavList(nested, baseURL: baseURL, rootURL: rootURL))
        }
    }

    private func parseNCX(at url: URL, rootURL: URL) -> [EPUBTOCItem] {
        guard let data = try? Data(contentsOf: url), let root = try? XMLTreeParser().parse(data), let navMap = root.first(named: "navmap") else { return [] }
        return parseNCXPoints(navMap.children.filter { $0.name == "navpoint" }, baseURL: url.deletingLastPathComponent(), rootURL: rootURL)
    }

    private func parseNCXPoints(_ points: [XMLNode], baseURL: URL, rootURL: URL) -> [EPUBTOCItem] {
        points.compactMap { point in
            guard let src = point.first(named: "content")?.attribute("src"), let target = try? safeRelativePath(src, relativeTo: baseURL, rootURL: rootURL) else { return nil }
            let children = parseNCXPoints(point.children.filter { $0.name == "navpoint" }, baseURL: baseURL, rootURL: rootURL)
            return EPUBTOCItem(label: cleanText(point.first(named: "text")?.textContent) ?? "未命名章节", href: target, children: children)
        }
    }

    private func coverPath(metadata: XMLNode?, manifest: [ManifestItem]) -> String? {
        if let coverID = metadata?.children.first(where: { $0.name == "meta" && $0.attribute("name")?.lowercased() == "cover" })?.attribute("content"), let item = manifest.first(where: { $0.id == coverID }) { return item.href }
        return manifest.first(where: { $0.properties.split(separator: " ").contains("cover-image") })?.href
    }

    private func tocTitle(for href: String, in items: [EPUBTOCItem]) -> String? {
        let path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        for item in items {
            if item.href.split(separator: "#", maxSplits: 1).first.map(String.init) == path { return item.label }
            if let nested = tocTitle(for: href, in: item.children) { return nested }
        }
        return nil
    }

    private func cleanText(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return value.isEmpty ? nil : value
    }

    private func safeURL(_ path: String, relativeTo baseURL: URL, rootURL: URL) throws -> URL {
        rootURL.appendingPathComponent(try safeRelativePath(path, relativeTo: baseURL, rootURL: rootURL))
    }

    private func safeRelativePath(_ path: String, relativeTo baseURL: URL, rootURL: URL) throws -> String {
        let pathPart = path.split(separator: "#", maxSplits: 1).first.map(String.init) ?? path
        let decoded = pathPart.removingPercentEncoding ?? pathPart
        let candidate = baseURL.appendingPathComponent(decoded).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard candidate.path.hasPrefix(rootPath + "/") else { throw EPUBImportError.invalidPackage("资源路径超出 EPUB 根目录") }
        return String(candidate.path.dropFirst(rootPath.count + 1))
    }
}
