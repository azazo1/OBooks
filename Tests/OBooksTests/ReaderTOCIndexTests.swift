import XCTest
@testable import OBooks

final class ReaderTOCIndexTests: XCTestCase {
    func testSelectsCurrentSectionAndKeepsPrecedingEntryForUnlistedSections() {
        let first = EPUBTOCItem(label: "第一章", href: "first.xhtml")
        let last = EPUBTOCItem(label: "第三章", href: "last.xhtml")
        let index = ReaderTOCIndex(
            spine: [spine("first"), spine("middle"), spine("last")],
            items: [first, last]
        )

        XCTAssertEqual(index.entryID(at: position("first", 0), anchors: [:]), first.id)
        XCTAssertEqual(index.entryID(at: position("middle", 80), anchors: [:]), first.id)
        XCTAssertEqual(index.entryID(at: position("last", 0), anchors: [:]), last.id)
        XCTAssertNil(index.entryID(at: position("unknown", 0), anchors: [:]))
    }

    func testSelectsDeepestReachedAnchorAndUpdatesWhenReadingBackwards() {
        let first = EPUBTOCItem(label: "第一节", href: "chapter.xhtml#first")
        let second = EPUBTOCItem(label: "第二节", href: "chapter.xhtml#second")
        let parent = EPUBTOCItem(label: "章节", href: "chapter.xhtml", children: [first, second])
        let index = ReaderTOCIndex(spine: [spine("chapter")], items: [parent])
        let anchors = ["first": 0, "second": 200]

        XCTAssertEqual(index.entries.map(\.depth), [0, 1, 1])
        XCTAssertEqual(index.entryID(at: position("chapter", 0), anchors: anchors), first.id)
        XCTAssertEqual(index.entryID(at: position("chapter", 199), anchors: anchors), first.id)
        XCTAssertEqual(index.entryID(at: position("chapter", 200), anchors: anchors), second.id)
        XCTAssertEqual(index.entryID(at: position("chapter", 40), anchors: anchors), first.id)
        XCTAssertEqual(index.entryID(at: position("chapter", 400), anchors: [:]), parent.id)
    }

    func testMatchesEncodedPathsAndAnchorsWithoutSpineID() {
        let chapter = EPUBSpineItem(id: "", href: "Text/第一章.xhtml", title: "", linear: true)
        let entry = EPUBTOCItem(label: "小节", href: "./Text/%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml#part%201")
        let index = ReaderTOCIndex(spine: [chapter], items: [entry])

        XCTAssertEqual(index.entries.first?.sectionIndex, 0)
        XCTAssertEqual(
            index.entryID(at: position(chapter.href, 50), anchors: ["part 1": 50]),
            entry.id
        )
    }

    func testDoesNotSelectFutureAnchorOrUnresolvedNavigationGroup() {
        let preceding = EPUBTOCItem(label: "前文", href: "before.xhtml")
        let upcoming = EPUBTOCItem(label: "后文", href: "chapter.xhtml#later")
        let group = EPUBTOCItem(label: "分组", href: "", children: [preceding, upcoming])
        let index = ReaderTOCIndex(spine: [spine("before"), spine("chapter")], items: [group])

        XCTAssertEqual(index.entryID(at: position("chapter", 50), anchors: ["later": 100]), preceding.id)
        XCTAssertEqual(index.entryID(at: position("chapter", 100), anchors: ["later": 100]), upcoming.id)
        XCTAssertNil(ReaderTOCIndex(spine: [], items: []).entryID(at: position("chapter", 0), anchors: [:]))
    }

    private func spine(_ id: String) -> EPUBSpineItem {
        EPUBSpineItem(id: id, href: "\(id).xhtml", title: id, linear: true)
    }

    private func position(_ spineID: String, _ offset: Int) -> ReadingPosition {
        ReadingPosition(spineID: spineID, characterOffset: offset)
    }
}
