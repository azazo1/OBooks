import Foundation

struct ReaderTOCIndex {
    struct Entry: Identifiable {
        let item: EPUBTOCItem
        let depth: Int
        let sectionIndex: Int?
        let anchor: String?
        var id: UUID { item.id }
    }

    let entries: [Entry]
    private let sectionIndices: [String: Int]

    init(spine: [EPUBSpineItem], items: [EPUBTOCItem]) {
        var paths: [String: Int] = [:]
        var identities: [String: Int] = [:]
        for (index, item) in spine.enumerated() {
            paths[Self.path(item.href)] = index
            identities[item.id.isEmpty ? item.href : item.id] = index
        }
        sectionIndices = identities

        func flatten(_ items: [EPUBTOCItem], depth: Int) -> [Entry] {
            items.flatMap { item in
                let fragment = URLComponents(string: item.href)?.fragment
                return [Entry(
                    item: item,
                    depth: depth,
                    sectionIndex: paths[Self.path(item.href)],
                    anchor: fragment?.isEmpty == false ? fragment : nil
                )] + flatten(item.children, depth: depth + 1)
            }
        }
        entries = flatten(items, depth: 0)
    }

    func entryID(at position: ReadingPosition, anchors: [String: Int]) -> UUID? {
        guard let sectionIndex = sectionIndices[position.spineID] else { return nil }
        var selected: Entry?
        var selectedOffset = -1
        for entry in entries where entry.sectionIndex == sectionIndex {
            let offset: Int?
            if let anchor = entry.anchor {
                offset = anchors[anchor]
            } else {
                offset = 0
            }
            guard let offset, offset <= position.characterOffset else { continue }
            if offset > selectedOffset || (offset == selectedOffset && entry.depth >= (selected?.depth ?? 0)) {
                selected = entry
                selectedOffset = offset
            }
        }
        if let selected { return selected.id }

        // 未单列目录的正文文件仍属于前一个目录项, 不提前选中尚未读到的小节.
        let precedingIndex = entries.compactMap(\.sectionIndex).filter { $0 < sectionIndex }.max()
        let preceding = precedingIndex.flatMap { index in entries.last { $0.sectionIndex == index } }
        return preceding?.id ?? entries.first { $0.sectionIndex == sectionIndex }?.id
    }

    private static func path(_ href: String) -> String {
        let path = URLComponents(string: href)?.path ?? href
        return (path as NSString).standardizingPath
    }
}
