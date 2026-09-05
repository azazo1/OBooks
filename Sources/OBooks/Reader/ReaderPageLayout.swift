import AppKit
import OSLog

@MainActor
struct ReaderPageLayout {
    let frames: [NSRect]
    let pageCount: Int
    let documentHeight: CGFloat

    init(layoutManager: NSLayoutManager, storage: NSTextStorage, viewport: NSSize,
         columns: Int, horizontalInset: CGFloat, verticalInset: CGFloat) {
        let columns = max(1, min(2, columns))
        let gap: CGFloat = columns == 2 ? 36 : 0
        let width = max(1, (viewport.width - horizontalInset * 2 - gap) / CGFloat(columns))
        let height = max(1, viewport.height - verticalInset * 2)
        let size = NSSize(width: width, height: height)
        while layoutManager.textContainers.count > 1 {
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        if layoutManager.textContainers.isEmpty {
            layoutManager.addTextContainer(NSTextContainer(size: size))
        }
        let first = layoutManager.textContainers[0]
        first.widthTracksTextView = false
        first.heightTracksTextView = false
        first.lineFragmentPadding = 0
        first.containerSize = size

        // 图片必须能完整放入一栏, 否则 TextKit 可能不断生成空容器.
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) {
            value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let image = attachment.image,
                  image.size.width > 0, image.size.height > 0 else { return }
            let scale = min(1, min(width, 720) / image.size.width, max(1, height - 8) / image.size.height)
            let bounds = NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
            if attachment.bounds != bounds {
                attachment.bounds = bounds
                layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            }
        }

        var coveredGlyphs = 0
        var containerIndex = 0
        while containerIndex < layoutManager.textContainers.count {
            let container = layoutManager.textContainers[containerIndex]
            layoutManager.ensureLayout(for: container)
            let range = layoutManager.glyphRange(for: container)
            let end = range.location == NSNotFound ? coveredGlyphs : NSMaxRange(range)
            if end >= layoutManager.numberOfGlyphs { break }
            guard end > coveredGlyphs else {
                Logger(subsystem: "com.obooks.app", category: "reader.pagination")
                    .error("分页无法容纳正文: glyph=\(coveredGlyphs), width=\(width), height=\(height)")
                break
            }
            coveredGlyphs = end
            let next = NSTextContainer(size: size)
            next.lineFragmentPadding = 0
            layoutManager.addTextContainer(next)
            containerIndex += 1
        }
        pageCount = max(1, (layoutManager.textContainers.count + columns - 1) / columns)
        frames = layoutManager.textContainers.indices.map { index in
            NSRect(
                x: horizontalInset + CGFloat(index % columns) * (width + gap),
                y: verticalInset + CGFloat(index / columns) * viewport.height,
                width: width, height: height
            )
        }
        documentHeight = CGFloat(pageCount) * viewport.height
    }
}
