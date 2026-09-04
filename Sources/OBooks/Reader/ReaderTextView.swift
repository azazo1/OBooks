import AppKit

@MainActor
final class ReaderTextView: NSTextView {
    var onHighlight: ((String, NSRange) -> Void)?
    var onNote: ((String, NSRange) -> Void)?
    var onSpeak: ((Int) -> Void)?
    var onLink: ((URL) -> Void)?
    var preferredReadingWidth: CGFloat = 820
    var minimumHorizontalInset: CGFloat = 34
    private var verticalInset: CGFloat = 52
    private var contextLocation = 0
    private var cursorTrackingArea: NSTrackingArea?
    private var pageColumns = 1
    private var pageViewportHeight: CGFloat = 0
    private var pageViewportSize = NSSize.zero
    private var pageOrientation: ReaderPageOrientation = .vertical
    private var paginatedLayout = false
    private var pageColumnFrames: [NSRect] = []
    private var isUpdatingPageLayout = false
    private var selectionAnchorLocation: Int?
    private var isSelectingAcrossColumns = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
    }

    func setReadingInsets(horizontal: CGFloat, vertical: CGFloat) {
        minimumHorizontalInset = horizontal
        verticalInset = vertical
        updateReadingInsets(for: bounds.width)
        window?.invalidateCursorRects(for: self)
    }

    func updateDocumentHeight(minimumHeight: CGFloat) {
        guard let layoutManager, let textContainer, bounds.width > 0 else { return }
        if paginatedLayout {
            updatePageLayout(minimumHeight: minimumHeight)
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = max(minimumHeight, ceil(usedRect.maxY + verticalInset * 2))
        guard abs(frame.height - requiredHeight) > 0.5 else { return }
        super.setFrameSize(NSSize(width: frame.width, height: requiredHeight))
        window?.invalidateCursorRects(for: self)
    }

    func updateDocumentSize(minimumSize: NSSize) {
        guard pageOrientation == .horizontal, paginatedLayout else {
            updateDocumentHeight(minimumHeight: minimumSize.height)
            return
        }
        updatePageLayout(minimumHeight: minimumSize.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged, paginatedLayout, pageOrientation == .vertical {
            pageViewportSize.width = max(1, newSize.width)
        }
        let insetWidth = paginatedLayout && pageOrientation == .horizontal
            ? pageViewportSize.width
            : newSize.width
        updateReadingInsets(for: insetWidth)
        if widthChanged && !isUpdatingPageLayout && !(paginatedLayout && pageOrientation == .horizontal) {
            updateDocumentHeight(minimumHeight: superview?.bounds.height ?? 0)
        }
    }

    func configurePageColumns(
        _ columns: Int,
        viewportHeight: CGFloat,
        orientation: ReaderPageOrientation = .vertical,
        paginated: Bool = true
    ) {
        configurePageColumns(
            columns,
            viewportSize: NSSize(width: bounds.width, height: viewportHeight),
            orientation: orientation,
            paginated: paginated
        )
    }

    func configurePageColumns(
        _ columns: Int,
        viewportSize: NSSize,
        orientation: ReaderPageOrientation,
        paginated: Bool
    ) {
        let normalized = max(1, min(2, columns))
        pageColumns = normalized
        pageViewportSize = NSSize(width: max(1, viewportSize.width), height: max(1, viewportSize.height))
        pageViewportHeight = pageViewportSize.height
        pageOrientation = orientation
        paginatedLayout = paginated
        autoresizingMask = orientation == .horizontal && paginated ? [] : [.width]
        if !paginated {
            removeAdditionalTextContainers()
            textContainer?.widthTracksTextView = true
            textContainer?.heightTracksTextView = false
            updateReadingInsets(for: bounds.width)
            return
        }
        updatePageLayout(minimumHeight: pageViewportSize.height)
    }

    func pageOffset(forCharacter location: Int) -> CGFloat? {
        guard paginatedLayout,
              let layoutManager,
              !pageColumnFrames.isEmpty else { return nil }
        for (index, container) in layoutManager.textContainers.enumerated() {
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { continue }
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            if NSLocationInRange(location, characterRange) ||
                location == NSMaxRange(characterRange) {
                let frame = pageColumnFrames[min(index, pageColumnFrames.count - 1)]
                return pageOrientation == .horizontal
                    ? pageViewportSize.width * CGFloat(index / pageColumns)
                    : frame.minY - verticalInset
            }
        }
        return nil
    }

    func visibleCharacterLocation() -> Int? {
        guard let layoutManager,
              let textContainer else { return nil }
        if !paginatedLayout {
            let origin = textContainerOrigin
            let visibleContainerRect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
            let glyphRange = layoutManager.glyphRange(
                forBoundingRect: visibleContainerRect,
                in: textContainer
            )
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { return nil }
            return layoutManager.characterIndexForGlyph(at: glyphRange.location)
        }
        var firstLocation: Int?
        for (index, container) in layoutManager.textContainers.enumerated() {
            guard pageColumnFrames.indices.contains(index) else { break }
            layoutManager.ensureLayout(for: container)
            let frame = pageColumnFrames[index]
            let intersection = visibleRect.intersection(frame)
            guard !intersection.isEmpty else { continue }
            let localRect = intersection.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y)
            let glyphRange = layoutManager.glyphRange(forBoundingRect: localRect, in: container)
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { continue }
            let location = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            firstLocation = firstLocation.map { min($0, location) } ?? location
        }
        return firstLocation
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard paginatedLayout,
              let layoutManager,
              pageColumnFrames.count > 1 else { return }
        for index in 1..<min(layoutManager.textContainers.count, pageColumnFrames.count) {
            let frame = pageColumnFrames[index]
            guard frame.intersects(dirtyRect) else { continue }
            let container = layoutManager.textContainers[index]
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { continue }
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: frame.origin)
            drawSelectionBackground(
                forGlyphRange: glyphRange,
                in: container,
                at: frame.origin,
                layoutManager: layoutManager
            )
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: frame.origin)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if let scrollView = enclosingScrollView as? ReaderScrollView {
            scrollView.notifyUserScroll()
            if scrollView.handlePageScroll(with: event) {
                return
            }
            if scrollView.handleScrollWheel(with: event) {
                return
            }
        }
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, let link = link(at: event) {
            onLink?(link)
            return
        }
        guard pageColumns > 1,
              event.clickCount == 1,
              event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }
        let location = characterLocation(for: event)
        selectionAnchorLocation = location
        isSelectingAcrossColumns = true
        window?.makeFirstResponder(self)
        updateCrossColumnSelection(NSRange(location: location, length: 0))
    }

    override func mouseDragged(with event: NSEvent) {
        guard pageColumns > 1,
              isSelectingAcrossColumns,
              let anchor = selectionAnchorLocation else {
            super.mouseDragged(with: event)
            return
        }
        let location = characterLocation(for: event)
        let range = NSRange(
            location: min(anchor, location),
            length: abs(location - anchor)
        )
        updateCrossColumnSelection(range)
    }

    override func mouseUp(with event: NSEvent) {
        guard pageColumns > 1,
              isSelectingAcrossColumns else {
            super.mouseUp(with: event)
            return
        }
        let location = characterLocation(for: event)
        if let anchor = selectionAnchorLocation {
            updateCrossColumnSelection(NSRange(
                location: min(anchor, location),
                length: abs(location - anchor)
            ))
        }
        selectionAnchorLocation = nil
        isSelectingAcrossColumns = false
    }

    override func resetCursorRects() {
        guard let layoutManager, let textStorage else { return }
        guard !visibleRect.isEmpty else { return }
        let string = textStorage.string as NSString
        for (index, textContainer) in layoutManager.textContainers.enumerated() {
            let origin = pageColumnFrames.indices.contains(index)
                ? pageColumnFrames[index].origin
                : textContainerOrigin
            let visibleContainerRect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
            let glyphRange = layoutManager.glyphRange(
                forBoundingRect: visibleContainerRect,
                in: textContainer
            )
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { continue }
            for glyphIndex in glyphRange.location..<NSMaxRange(glyphRange) {
                let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                guard characterIndex < textStorage.length,
                      textStorage.attribute(.attachment, at: characterIndex, effectiveRange: nil) == nil
                else { continue }

                let characterRange = NSRange(location: characterIndex, length: 1)
                guard string.rangeOfCharacter(
                    from: .whitespacesAndNewlines,
                    options: [],
                    range: characterRange
                ).location == NSNotFound else { continue }

                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1),
                    in: textContainer
                )
                guard !glyphRect.isEmpty else { continue }
                addCursorRect(
                    glyphRect.offsetBy(dx: origin.x, dy: origin.y),
                    cursor: NSCursor.iBeam
                )
            }
        }
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        super.updateTrackingAreas()
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private func updateCursor(for event: NSEvent) {
        NSCursor.arrow.set()
        guard let layoutManager, let textStorage else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let (textContainer, origin) = textContainerContext(at: point) else { return }
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.contains(containerPoint) else { return }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length,
              textStorage.attribute(.attachment, at: characterIndex, effectiveRange: nil) == nil
        else { return }
        let character = (textStorage.string as NSString).substring(
            with: NSRange(location: characterIndex, length: 1)
        )
        guard character.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return }
        NSCursor.iBeam.set()
    }

    private func link(at event: NSEvent) -> URL? {
        guard let layoutManager else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let (textContainer, origin) = textContainerContext(at: point) else { return nil }
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard let textStorage,
              characterIndex < textStorage.length,
              let link = textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) as? URL else { return nil }
        return link
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let range = validSelectionRange() ?? NSRange(location: 0, length: 0)
        contextLocation = range.length > 0 ? range.location : characterLocation(for: event)
        let menu = NSMenu(title: "阅读")
        menu.autoenablesItems = false

        if range.length > 0 {
            menu.addItem(menuItem(title: "高亮", symbol: "highlighter", action: #selector(highlightSelection)))
            menu.addItem(menuItem(title: "添加笔记", symbol: "note.text", action: #selector(addNote)))
        }
        menu.addItem(menuItem(title: "从此处开始朗读", symbol: "speaker.wave.2", action: #selector(speakFromSelection)))
        if range.length > 0 {
            menu.addItem(.separator())
            menu.addItem(menuItem(title: "拷贝", symbol: "doc.on.doc", action: #selector(copySelection)))
        }
        return menu
    }

    @objc private func highlightSelection() {
        guard let range = validSelectionRange(), range.length > 0 else { return }
        onHighlight?((string as NSString).substring(with: range), range)
        setSelectedRange(NSRange(location: range.location + range.length, length: 0))
    }

    @objc private func addNote() {
        guard let range = validSelectionRange(), range.length > 0 else { return }
        onNote?((string as NSString).substring(with: range), range)
    }

    @objc private func speakFromSelection() {
        onSpeak?(min(contextLocation, (string as NSString).length))
    }

    @objc private func copySelection() {
        copy(nil)
    }

    private func updateReadingInsets(for width: CGFloat) {
        let centeredInset = (width - preferredReadingWidth) / 2
        let horizontalInset = max(minimumHorizontalInset, centeredInset)
        let nextInset = NSSize(width: horizontalInset, height: verticalInset)
        if textContainerInset != nextInset {
            textContainerInset = nextInset
        }
    }

    private func updateCrossColumnSelection(_ range: NSRange) {
        let length = (string as NSString).length
        let clampedLocation = min(max(range.location, 0), length)
        let clampedLength = min(max(range.length, 0), length - clampedLocation)
        setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
        needsDisplay = true
    }

    private func updatePageLayout(minimumHeight: CGFloat) {
        guard !isUpdatingPageLayout,
              paginatedLayout,
              let layoutManager,
              let textContainer,
              let textStorage else { return }
        isUpdatingPageLayout = true
        defer { isUpdatingPageLayout = false }

        let viewportWidth = max(pageViewportSize.width, 1)
        let viewportHeight = max(pageViewportHeight, minimumHeight, 1)
        let horizontalInset = max(minimumHorizontalInset, (viewportWidth - preferredReadingWidth) / 2)
        let gap: CGFloat = 28
        let availableWidth = max(240, viewportWidth - horizontalInset * 2 - gap * CGFloat(pageColumns - 1))
        let columnWidth = availableWidth / CGFloat(pageColumns)
        let columnHeight = max(120, viewportHeight - verticalInset * 2)
        let fontSize = textStorage.length > 0
            ? textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            : nil
        let charactersPerColumn = max(
            260,
            Int((columnWidth / max(fontSize?.pointSize ?? 18, 12)) * 27)
        )
        let pageCount = max(
            1,
            Int(ceil(Double(max(textStorage.length, 1)) / Double(charactersPerColumn * pageColumns))) + 1
        )
        let containerCount = pageCount * pageColumns

        removeAdditionalTextContainers()
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.containerSize = NSSize(width: columnWidth, height: columnHeight)
        for _ in 1..<containerCount {
            let container = NSTextContainer(size: NSSize(width: columnWidth, height: columnHeight))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
        }

        for container in layoutManager.textContainers {
            layoutManager.ensureLayout(for: container)
        }
        while let lastContainer = layoutManager.textContainers.last {
            let lastRange = layoutManager.glyphRange(for: lastContainer)
            let hasMoreGlyphs = lastRange.location != NSNotFound
                && NSMaxRange(lastRange) < layoutManager.numberOfGlyphs
            if hasMoreGlyphs {
                for _ in 0..<pageColumns {
                    let container = NSTextContainer(size: NSSize(width: columnWidth, height: columnHeight))
                    container.lineFragmentPadding = 0
                    layoutManager.addTextContainer(container)
                    layoutManager.ensureLayout(for: container)
                }
                continue
            }
            if layoutManager.textContainers.count > pageColumns, lastRange.length == 0 {
                layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
                continue
            }
            break
        }

        let finalPageCount = max(1, Int(ceil(Double(layoutManager.textContainers.count) / 2)))

        pageColumnFrames = (0..<layoutManager.textContainers.count).map { index in
            let page = index / pageColumns
            let column = index % pageColumns
            let pageOrigin = pageOrientation == .horizontal
                ? CGFloat(page) * viewportWidth
                : 0
            return NSRect(
                x: pageOrigin + horizontalInset + CGFloat(column) * (columnWidth + gap),
                y: pageOrientation == .horizontal
                    ? verticalInset
                    : verticalInset + CGFloat(page) * viewportHeight,
                width: columnWidth,
                height: columnHeight
            )
        }
        let documentSize = pageOrientation == .horizontal
            ? NSSize(
                width: max(viewportWidth, CGFloat(finalPageCount) * viewportWidth),
                height: viewportHeight
            )
            : NSSize(
                width: frame.width,
                height: max(viewportHeight, CGFloat(finalPageCount) * viewportHeight + verticalInset * 2)
            )
        if abs(frame.width - documentSize.width) > 0.5 || abs(frame.height - documentSize.height) > 0.5 {
            super.setFrameSize(documentSize)
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func drawSelectionBackground(
        forGlyphRange glyphRange: NSRange,
        in textContainer: NSTextContainer,
        at origin: NSPoint,
        layoutManager: NSLayoutManager
    ) {
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        let selectedGlyphRange = layoutManager.glyphRange(
            forCharacterRange: selection,
            actualCharacterRange: nil
        )
        guard selectedGlyphRange.length > 0 else { return }
        let intersection = NSIntersectionRange(glyphRange, selectedGlyphRange)
        guard intersection.length > 0 else { return }
        let color = selectedTextAttributes[.backgroundColor] as? NSColor
            ?? NSColor.selectedTextBackgroundColor
        color.setFill()
        layoutManager.enumerateLineFragments(forGlyphRange: intersection) {
            _, usedRect, container, lineGlyphRange, _ in
            guard container === textContainer else { return }
            let lineIntersection = NSIntersectionRange(lineGlyphRange, intersection)
            guard lineIntersection.length > 0 else { return }
            var rect = usedRect
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: lineIntersection,
                in: textContainer
            )
            if !glyphRect.isEmpty {
                rect.origin.x = glyphRect.minX
                rect.size.width = glyphRect.width
            }
            rect = rect.offsetBy(dx: origin.x, dy: origin.y)
            NSBezierPath(rect: rect).fill()
        }
    }

    private func removeAdditionalTextContainers() {
        guard let layoutManager else { return }
        while layoutManager.textContainers.count > 1 {
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        pageColumnFrames.removeAll()
    }

    private func validSelectionRange() -> NSRange? {
        let range = selectedRange()
        let length = (string as NSString).length
        guard range.location != NSNotFound,
              range.location <= length,
              range.length <= length - range.location else { return nil }
        return range
    }

    private func characterLocation(for event: NSEvent) -> Int {
        guard let layoutManager else { return selectedRange().location }
        let point = convert(event.locationInWindow, from: nil)
        guard let (textContainer, origin) = textContainerContext(at: point) else {
            return selectedRange().location
        }
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let containerGlyphRange = layoutManager.glyphRange(for: textContainer)
        guard containerGlyphRange.length > 0 else {
            return characterBoundary(for: textContainer, layoutManager: layoutManager)
        }
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        if glyphIndex >= NSMaxRange(containerGlyphRange) {
            return NSMaxRange(layoutManager.characterRange(
                forGlyphRange: containerGlyphRange,
                actualGlyphRange: nil
            ))
        }
        return layoutManager.characterIndexForGlyph(
            at: max(containerGlyphRange.location, glyphIndex)
        )
    }

    private func characterBoundary(
        for textContainer: NSTextContainer,
        layoutManager: NSLayoutManager
    ) -> Int {
        guard let index = layoutManager.textContainers.firstIndex(where: { $0 === textContainer }) else {
            return (string as NSString).length
        }
        for previousIndex in stride(from: index - 1, through: 0, by: -1) {
            let glyphRange = layoutManager.glyphRange(for: layoutManager.textContainers[previousIndex])
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { continue }
            return NSMaxRange(layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            ))
        }
        return 0
    }

    private func textContainerContext(at point: NSPoint) -> (NSTextContainer, NSPoint)? {
        guard let layoutManager else { return nil }
        if pageColumns > 1 {
            if let (index, frame) = pageColumnFrames.enumerated().first(where: { $0.element.contains(point) }),
               layoutManager.textContainers.indices.contains(index) {
                return (layoutManager.textContainers[index], frame.origin)
            }
            if let (index, frame) = pageColumnFrames.enumerated().min(by: {
                distance(from: point, to: $0.element) < distance(from: point, to: $1.element)
            }), layoutManager.textContainers.indices.contains(index) {
                return (layoutManager.textContainers[index], frame.origin)
            }
        }
        guard let textContainer else { return nil }
        return (textContainer, textContainerOrigin)
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }
        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }
        return hypot(dx, dy)
    }

    private func menuItem(title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.isEnabled = true
        return item
    }
}
