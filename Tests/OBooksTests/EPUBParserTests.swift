import Foundation
import XCTest
@testable import OBooks

final class EPUBParserTests: XCTestCase {
    func testParsesEPUBPackageAndNavigation() throws {
        let root = try makePackage(includeEncryption: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let info = try EPUBParser().parse(folderURL: root)

        XCTAssertEqual(info.title, "OBooks Test")
        XCTAssertEqual(info.authors, ["Reader Author"])
        XCTAssertEqual(info.spine.count, 2)
        XCTAssertEqual(info.spine[0].href, "OEBPS/Text/chapter-1.xhtml")
        XCTAssertEqual(info.spine[0].title, "Chapter One")
        XCTAssertEqual(info.toc.first?.label, "Chapter One")
        XCTAssertEqual(info.toc.first?.href, "OEBPS/Text/chapter-1.xhtml#section")
    }

    func testRejectsEncryptedPackage() throws {
        let root = try makePackage(includeEncryption: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try EPUBParser().parse(folderURL: root)) { error in
            XCTAssertEqual(error as? EPUBImportError, .encryptedPublication)
        }
    }

    private func makePackage(includeEncryption: Bool) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("obooks-test-" + UUID().uuidString, isDirectory: true)
        let metaInf = root.appendingPathComponent("META-INF", isDirectory: true)
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        let text = oebps.appendingPathComponent("Text", isDirectory: true)
        try fileManager.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: text, withIntermediateDirectories: true)

        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """, to: metaInf.appendingPathComponent("container.xml"))

        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="book-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">test-book</dc:identifier>
            <dc:title>OBooks Test</dc:title>
            <dc:creator>Reader Author</dc:creator>
          </metadata>
          <manifest>
            <item id="chapter-1" href="Text/chapter-1.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter-2" href="Text/chapter-2.xhtml" media-type="application/xhtml+xml"/>
            <item id="toc" href="Text/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
          </manifest>
          <spine>
            <itemref idref="chapter-1"/>
            <itemref idref="chapter-2"/>
          </spine>
        </package>
        """, to: oebps.appendingPathComponent("content.opf"))

        try write("""
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <body><nav epub:type="toc"><ol><li><a href="chapter-1.xhtml#section">Chapter One</a></li><li><a href="chapter-2.xhtml">Chapter Two</a></li></ol></nav></body>
        </html>
        """, to: text.appendingPathComponent("nav.xhtml"))
        try write("<html><body><p>One</p></body></html>", to: text.appendingPathComponent("chapter-1.xhtml"))
        try write("<html><body><p>Two</p></body></html>", to: text.appendingPathComponent("chapter-2.xhtml"))
        if includeEncryption { try write("<encryption xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"/>", to: metaInf.appendingPathComponent("encryption.xml")) }
        return root
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }
}
