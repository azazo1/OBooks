import Foundation

struct ReaderImagePreviewMetrics: Equatable {
    var imageSize: CGSize
    var canvasSize: CGSize
    var horizontalInset: CGFloat = 22
    var verticalInset: CGFloat = 52

    var contentSize: CGSize {
        CGSize(
            width: max(1, canvasSize.width - horizontalInset * 2),
            height: max(1, canvasSize.height - verticalInset * 2)
        )
    }

    /// Scale from image pixels to the fitted box. Values above 1 upscale small images.
    var fitScale: CGFloat {
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let content = contentSize
        return min(content.width / width, content.height / height)
    }

    var fittedSize: CGSize {
        CGSize(
            width: max(1, imageSize.width) * fitScale,
            height: max(1, imageSize.height) * fitScale
        )
    }

    /// 1:1 if that zooms in, otherwise 2x the fitted size.
    var magnifiedZoom: CGFloat {
        max(2, 1 / max(fitScale, 0.001))
    }

    func displayedSize(zoom: CGFloat) -> CGSize {
        let size = fittedSize
        return CGSize(width: size.width * zoom, height: size.height * zoom)
    }

    func imageRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let size = displayedSize(zoom: zoom)
        return CGRect(
            x: (canvasSize.width - size.width) / 2 + offset.width,
            y: (canvasSize.height - size.height) / 2 + offset.height,
            width: size.width,
            height: size.height
        )
    }

    func contains(_ point: CGPoint, zoom: CGFloat, offset: CGSize) -> Bool {
        imageRect(zoom: zoom, offset: offset).contains(point)
    }

    func toggledZoom(_ zoom: CGFloat) -> CGFloat {
        zoom > 1.01 ? 1 : magnifiedZoom
    }

    func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(1, zoom), max(8, magnifiedZoom))
    }

    func clampedOffset(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let displayed = displayedSize(zoom: zoom)
        let content = contentSize
        let horizontalLimit = max(0, (displayed.width - content.width) / 2)
        let verticalLimit = max(0, (displayed.height - content.height) / 2)
        return CGSize(
            width: min(horizontalLimit, max(-horizontalLimit, offset.width)),
            height: min(verticalLimit, max(-verticalLimit, offset.height))
        )
    }
}
