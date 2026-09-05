import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderImageExportTests: XCTestCase {
    func testExportPreservesFullResolutionAndTransparency() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("image.png")
        let image = NSImage(size: NSSize(width: 80, height: 45))
        image.addRepresentation(try makeBitmap(width: 80, height: 45))
        let fullSizeBitmap = try makeBitmap(width: 320, height: 180)
        var sourcePixel = [255, 0, 0, 128]
        fullSizeBitmap.setPixel(&sourcePixel, atX: 10, y: 20)
        image.addRepresentation(fullSizeBitmap)

        try ReaderImageExporter.writePNG(image, to: url)

        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let exported = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(exported.pixelsWide, 320)
        XCTAssertEqual(exported.pixelsHigh, 180)
        var exportedPixel = [Int](repeating: 0, count: 4)
        exported.getPixel(&exportedPixel, atX: 10, y: 20)
        XCTAssertEqual(exportedPixel, sourcePixel)
    }

    func testExportFailureKeepsExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("existing.png")
        let original = Data([1, 2, 3])
        try original.write(to: url)

        XCTAssertThrowsError(try ReaderImageExporter.writePNG(NSImage(size: .zero), to: url))
        XCTAssertEqual(try Data(contentsOf: url), original)

        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.addRepresentation(try makeBitmap(width: 8, height: 8))
        XCTAssertThrowsError(try ReaderImageExporter.writePNG(image, to: directory))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    private func makeBitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaNonpremultiplied],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try XCTUnwrap(bitmap.retagging(with: .sRGB))
    }
}
