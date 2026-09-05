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
        guard zoom > 1.01 else { return .zero }
        let displayed = displayedSize(zoom: zoom)
        let content = contentSize
        let horizontalLimit = panLimit(displayed: displayed.width, viewport: content.width)
        let verticalLimit = panLimit(displayed: displayed.height, viewport: content.height)
        return CGSize(
            width: min(horizontalLimit, max(-horizontalLimit, offset.width)),
            height: min(verticalLimit, max(-verticalLimit, offset.height))
        )
    }

    /// 确保视口内始终保留一部分图片, 同时允许图片边缘拖动至视口中央.
    func panLimit(displayed: CGFloat, viewport: CGFloat) -> CGFloat {
        let minVisible = min(120, viewport * 0.25)
        return max(0, (displayed + viewport) / 2 - minVisible)
    }

    static func scrollEffect(
        deltaX: CGFloat,
        deltaY: CGFloat,
        command: Bool,
        shift: Bool
    ) -> (zoomStep: CGFloat, pan: CGSize) {
        if command {
            let delta = deltaY != 0 ? deltaY : deltaX
            return (max(-0.65, min(0.65, delta * 0.012)), .zero)
        }
        let horizontal: CGFloat
        if abs(deltaX) > 0.01 {
            horizontal = deltaX
        } else if shift {
            horizontal = deltaY
        } else {
            horizontal = 0
        }
        return (0, CGSize(width: horizontal, height: shift ? 0 : deltaY))
    }
}
