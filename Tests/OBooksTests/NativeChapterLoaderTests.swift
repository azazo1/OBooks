import AppKit
import XCTest
@testable import OBooks

final class NativeChapterLoaderTests: XCTestCase {
    func testPreservesMixedContentOrderAndTextStyles() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let chapterURL = rootURL.appendingPathComponent("chapter.xhtml")
        let data = Data("""
        <html xmlns="http://www.w3.org/1999/xhtml">
          <body>
            <h1>Chapter <em>One</em></h1>
            <p>Hello <strong>native</strong> reader.</p>
            <script>ignored()</script>
          </body>
        </html>
        """.utf8)

        let result = try NativeChapterLoader().load(
            data: data,
            chapterURL: chapterURL,
            rootURL: rootURL,
            fontSize: 18,
            lineHeight: 1.7,
            foreground: .textColor
        )

        XCTAssertEqual(result.string.split(whereSeparator: \.isNewline).map(String.init), [
            "Chapter One",
            "Hello native reader."
        ])
        let nativeRange = (result.string as NSString).range(of: "native")
        let nativeFont = try XCTUnwrap(result.attribute(.font, at: nativeRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: nativeFont).contains(.boldFontMask))
        let chapterRange = (result.string as NSString).range(of: "Chapter")
        let chapterFont = try XCTUnwrap(result.attribute(.font, at: chapterRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(chapterFont.pointSize, 18)
        XCTAssertFalse(result.string.contains("ignored"))
    }
}
