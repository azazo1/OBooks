import AppKit
import XCTest
@testable import OBooks

final class NativeChapterLoaderTests: XCTestCase {
    func testRendersImageAndImageAttachments() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let chapterURL = rootURL.appendingPathComponent("chapter.xhtml")
        let imageURL = rootURL.appendingPathComponent("figure.tiff")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 320,
            pixelsHigh: 180,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let image = NSImage(size: NSSize(width: 320, height: 180))
        image.addRepresentation(bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: imageURL)
        let data = Data("""
        <html xmlns="http://www.w3.org/1999/xhtml">
          <body><p><img src="figure.tiff" /><image href="figure.tiff" /></p></body>
        </html>
        """.utf8)

        let document = try NativeChapterLoader().loadDocument(
            data: data,
            chapterURL: chapterURL,
            rootURL: rootURL,
            fontSize: 18,
            lineHeight: 1.7,
            foreground: .textColor
        )

        let attachments = (0..<document.attributedText.length).compactMap { index in
            document.attributedText.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment
        }
        XCTAssertEqual(attachments.count, 2)
        XCTAssertTrue(attachments.allSatisfy { $0.image?.size == image.size })
    }

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

    func testRendersHTMLCSSAndAnchors() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let chapterURL = rootURL.appendingPathComponent("chapter.xhtml")
        let data = Data("""
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><style>
            body { font-size: 20px; color: #ff0000; }
            .note { font-weight: bold; text-align: center; }
          </style></head>
          <body>
            <p id="intro">Intro</p>
            <div class="note">Styled</div>
            <p><a href="#intro">Back</a></p>
          </body>
        </html>
        """.utf8)

        let document = try NativeChapterLoader().loadDocument(
            data: data,
            chapterURL: chapterURL,
            rootURL: rootURL,
            fontSize: 18,
            lineHeight: 1.7,
            foreground: .textColor
        )

        XCTAssertEqual(document.attributedText.string.split(whereSeparator: \.isNewline).map(String.init), ["Intro", "Styled", "Back"])
        XCTAssertEqual(document.anchors["intro"], 0)
        let styledRange = (document.attributedText.string as NSString).range(of: "Styled")
        let styledFont = try XCTUnwrap(document.attributedText.attribute(.font, at: styledRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(styledFont.pointSize, 18)
        XCTAssertTrue(NSFontManager.shared.traits(of: styledFont).contains(.boldFontMask))
        let paragraph = try XCTUnwrap(document.attributedText.attribute(.paragraphStyle, at: styledRange.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(paragraph.alignment, .center)
        let color = try XCTUnwrap(document.attributedText.attribute(.foregroundColor, at: styledRange.location, effectiveRange: nil) as? NSColor)
        let rgbColor = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
        XCTAssertEqual(Double(rgbColor.redComponent), 1, accuracy: 0.01)
        let linkRange = (document.attributedText.string as NSString).range(of: "Back")
        let link = try XCTUnwrap(document.attributedText.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(link.fragment, "intro")
    }
}
