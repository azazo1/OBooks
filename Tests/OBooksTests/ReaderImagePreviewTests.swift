import XCTest
@testable import OBooks

final class ReaderImagePreviewTests: XCTestCase {
    func testSmallImageOpensByUpscalingToFit() {
        let metrics = ReaderImagePreviewMetrics(
            imageSize: CGSize(width: 200, height: 100),
            canvasSize: CGSize(width: 1044, height: 800)
        )
        XCTAssertEqual(metrics.fitScale, 5, accuracy: 0.001)
        XCTAssertEqual(metrics.displayedSize(zoom: 1).width, 1000, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.fitScale, 1)
    }

    func testLargeImageOpensFittedBelowNativeSize() {
        let metrics = ReaderImagePreviewMetrics(
            imageSize: CGSize(width: 4000, height: 2000),
            canvasSize: CGSize(width: 1044, height: 800)
        )
        XCTAssertEqual(metrics.fitScale, 0.25, accuracy: 0.001)
        XCTAssertEqual(metrics.displayedSize(zoom: 1).width, 1000, accuracy: 0.001)
    }

    func testDoubleClickMagnifiesThenRestores() {
        let small = ReaderImagePreviewMetrics(
            imageSize: CGSize(width: 200, height: 100),
            canvasSize: CGSize(width: 1044, height: 800)
        )
        XCTAssertEqual(small.toggledZoom(1), 2, accuracy: 0.001)
        XCTAssertEqual(small.toggledZoom(2), 1, accuracy: 0.001)

        let large = ReaderImagePreviewMetrics(
            imageSize: CGSize(width: 4000, height: 2000),
            canvasSize: CGSize(width: 1044, height: 800)
        )
        XCTAssertEqual(large.toggledZoom(1), 4, accuracy: 0.001)
        XCTAssertEqual(large.toggledZoom(4), 1, accuracy: 0.001)
    }

    func testScrollWheelPansAndCommandZooms() {
        let pan = ReaderImagePreviewMetrics.scrollEffect(
            deltaX: 12, deltaY: -30, command: false, shift: false
        )
        XCTAssertEqual(pan.zoomStep, 0)
        XCTAssertEqual(pan.pan.width, 12)
        XCTAssertEqual(pan.pan.height, -30)

        let shifted = ReaderImagePreviewMetrics.scrollEffect(
            deltaX: 0, deltaY: 20, command: false, shift: true
        )
        XCTAssertEqual(shifted.pan.width, 20)
        XCTAssertEqual(shifted.pan.height, 0)

        let zoom = ReaderImagePreviewMetrics.scrollEffect(
            deltaX: 0, deltaY: 50, command: true, shift: false
        )
        XCTAssertEqual(zoom.zoomStep, 0.6, accuracy: 0.0001)
        XCTAssertEqual(zoom.pan, .zero)
    }

    func testBlankPointIsOutsideFittedImage() {
        let metrics = ReaderImagePreviewMetrics(
            imageSize: CGSize(width: 200, height: 100),
            canvasSize: CGSize(width: 1044, height: 800)
        )
        XCTAssertTrue(metrics.contains(CGPoint(x: 522, y: 400), zoom: 1, offset: .zero))
        XCTAssertFalse(metrics.contains(CGPoint(x: 8, y: 8), zoom: 1, offset: .zero))
        XCTAssertFalse(metrics.contains(CGPoint(x: 522, y: 20), zoom: 1, offset: .zero))
    }
}
