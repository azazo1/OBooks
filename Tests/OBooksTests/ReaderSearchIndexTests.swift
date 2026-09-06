import XCTest
@testable import OBooks

final class ReaderSearchIndexTests: XCTestCase {
    func testFindsCaseInsensitiveOccurrencesAndCapsPerChapter() {
        let repeated = Array(repeating: "Apple banana apple", count: 10).joined(separator: "\n")
        let hits = ReaderSearchIndex.hits(
            in: repeated,
            query: "APPLE",
            sectionIndex: 2,
            spineID: "ch-2",
            title: "Fruit"
        )

        XCTAssertEqual(hits.count, ReaderSearchIndex.maxHitsPerChapter)
        XCTAssertEqual(hits.map(\.occurrenceIndex), Array(0..<ReaderSearchIndex.maxHitsPerChapter))
        XCTAssertEqual(Set(hits.map(\.sectionIndex)), [2])
        XCTAssertEqual(Set(hits.map(\.spineID)), ["ch-2"])
        XCTAssertTrue(hits.allSatisfy { $0.query == "APPLE" })
        XCTAssertGreaterThan(hits[1].characterOffset, hits[0].characterOffset)
    }

    func testSnippetRangeCoversTheMatchedText() {
        let text = "prefix " + String(repeating: "x", count: 80) + " target word " + String(repeating: "y", count: 80)
        let hits = ReaderSearchIndex.hits(
            in: text,
            query: "target",
            sectionIndex: 0,
            spineID: "spine",
            title: "Chapter"
        )

        XCTAssertEqual(hits.count, 1)
        let hit = hits[0]
        let snippet = hit.snippet as NSString
        XCTAssertEqual(snippet.substring(with: hit.matchRangeInSnippet).lowercased(), "target")
        XCTAssertTrue(hit.snippet.hasPrefix("..."))
        XCTAssertTrue(hit.snippet.hasSuffix("..."))
    }

    func testIgnoresEmptyQueryAndMissingText() {
        XCTAssertTrue(
            ReaderSearchIndex.hits(
                in: "hello",
                query: "   ",
                sectionIndex: 0,
                spineID: "a",
                title: "A"
            ).isEmpty
        )
        XCTAssertTrue(
            ReaderSearchIndex.hits(
                in: "",
                query: "hello",
                sectionIndex: 0,
                spineID: "a",
                title: "A"
            ).isEmpty
        )
    }

    func testChapterTitlePrefersTOCThenSpineThenFallback() {
        let spine = [
            EPUBSpineItem(id: "one", href: "one.xhtml", title: "Spine One", linear: true),
            EPUBSpineItem(id: "two", href: "two.xhtml", title: "  ", linear: true),
            EPUBSpineItem(id: "three", href: "three.xhtml", title: "", linear: true)
        ]
        let toc = [
            EPUBTOCItem(label: "目录一", href: "one.xhtml"),
            EPUBTOCItem(label: "目录二", href: "two.xhtml")
        ]
        let index = ReaderTOCIndex(spine: spine, items: toc)
        let book = BookSummary(
            id: UUID(),
            title: "Demo",
            authors: [],
            sortTitle: "demo",
            sourceFileName: "demo.epub",
            folderName: UUID().uuidString,
            coverPath: nil,
            spine: spine,
            toc: toc,
            progressFraction: 0,
            lastOpenedAt: nil,
            importedAt: Date()
        )

        XCTAssertEqual(ReaderSearchIndex.chapterTitle(book: book, tocIndex: index, sectionIndex: 0), "目录一")
        XCTAssertEqual(ReaderSearchIndex.chapterTitle(book: book, tocIndex: index, sectionIndex: 1), "目录二")
        XCTAssertEqual(ReaderSearchIndex.chapterTitle(book: book, tocIndex: index, sectionIndex: 2), "目录二")
        XCTAssertEqual(ReaderSearchIndex.chapterTitle(book: book, tocIndex: index, sectionIndex: 9), "第 10 章")
    }
}

final class ReaderSearchTextExtractorTests: XCTestCase {
    func testExtractsVisibleTextAndSkipsScriptStyleAndImages() throws {
        let data = Data("""
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>Ignored</title><style>p { color: red; }</style></head>
          <body>
            <h1>Chapter <em>One</em></h1>
            <p>Hello <strong>native</strong> reader.</p>
            <script>ignored()</script>
            <p><img src="figure.png" />After image</p>
          </body>
        </html>
        """.utf8)

        let text = try ReaderSearchTextExtractor().extract(data: data)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)

        XCTAssertEqual(lines, [
            "Chapter One",
            "Hello native reader.",
            "After image"
        ])
        XCTAssertFalse(text.contains("ignored"))
        XCTAssertFalse(text.contains("Ignored"))
        XCTAssertFalse(text.contains("color"))
    }

    func testRejectsInvalidSectionIndex() {
        let book = BookSummary(
            id: UUID(),
            title: "Demo",
            authors: [],
            sortTitle: "demo",
            sourceFileName: "demo.epub",
            folderName: UUID().uuidString,
            coverPath: nil,
            spine: [],
            toc: [],
            progressFraction: 0,
            lastOpenedAt: nil,
            importedAt: Date()
        )
        XCTAssertThrowsError(try ReaderSearchTextExtractor().extract(book: book, sectionIndex: 0))
    }
}
