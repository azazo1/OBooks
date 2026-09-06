import AppKit

@MainActor
final class ReaderTextView: NSTextView {
    var onHighlight: ((String, NSRange) -> Void)?
    var onNote: ((String, NSRange) -> Void)?
    var onAnnotationClick: ((ReaderAnnotation) -> Void)?
    var annotationAtLocation: ((Int) -> ReaderAnnotation?)?
    var onRemoveAnnotation: ((UUID) -> Void)?
    var onSpeak: ((Int) -> Void)?
    var onLink: ((URL) -> Void)?
    var onImageClick: ((NSImage, NSRect) -> Void)?
    var allowsImagePreview = true
    var onSpeechInteraction: ((Bool) -> Void)?
    var preferredReadingWidth: CGFloat = 1150
    var minimumHorizontalInset: CGFloat = 34
    private var verticalInset: CGFloat = 52
    private var contextLocation = 0
    private var contextAnnotationID: UUID?
    private var pageColumns = 0
    private(set) var pageViewportHeight: CGFloat = 0
    private(set) var pageCount = 1
    private var pageColumnFrames: [NSRect] = []
    private var isUpdatingPageLayout = false
    private var selectionAnchorLocation: Int?
    private var isSelectingPageText = false
    private var pendingImageHit: (image: NSImage, rect: NSRect)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
        if pageColumns > 0 {
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

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        var documentSize = newSize
        if pageColumns > 0, !isUpdatingPageLayout, !pageColumnFrames.isEmpty {
            // 原生尺寸调整只了解首个文本容器, 分页高度必须由完整页数决定.
            documentSize.height = CGFloat(pageCount) * pageViewportHeight
        }
        super.setFrameSize(documentSize)
        updateReadingInsets(for: newSize.width)
        if widthChanged && !isUpdatingPageLayout {
            updateDocumentHeight(minimumHeight: superview?.bounds.height ?? 0)
        }
        window?.invalidateCursorRects(for: self)
    }

    func configurePageColumns(_ columns: Int, viewportHeight: CGFloat) {
        let normalized = max(0, min(2, columns))
        pageColumns = normalized
        pageViewportHeight = max(1, viewportHeight)
        isVerticallyResizable = normalized == 0
        if normalized == 0 {
            removeAdditionalTextContainers()
            pageCount = 1
            textContainer?.widthTracksTextView = true
            textContainer?.heightTracksTextView = false
            textContainer?.containerSize = NSSize(
                width: max(1, bounds.width - textContainerInset.width * 2),
                height: CGFloat.greatestFiniteMagnitude
            )
            updateReadingInsets(for: bounds.width)
            return
        }
        updatePageLayout(minimumHeight: pageViewportHeight)
    }

    func pageOffset(forCharacter location: Int) -> CGFloat? {
        guard pageColumns > 0,
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
                (location == (string as NSString).length && location == NSMaxRange(characterRange)) {
                return pageColumnFrames[min(index, pageColumnFrames.count - 1)].minY - verticalInset
            }
        }
        return nil
    }

    func visibleCharacterLocation() -> Int? {
        guard let layoutManager,
              let textContainer else { return nil }
        if pageColumns == 0 {
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

    func documentY(forCharacter location: Int) -> CGFloat? {
        guard pageColumns == 0,
              let layoutManager,
              let textContainer else { return nil }
        let length = (string as NSString).length
        guard length > 0 else { return nil }
        let clampedLocation = min(max(location, 0), length - 1)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: clampedLocation, length: 1),
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0, glyphRange.location != NSNotFound else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return rect.minY + textContainerOrigin.y
    }

    func viewportOffset(forCharacter location: Int) -> CGFloat? {
        guard let documentY = documentY(forCharacter: location) else { return nil }
        return documentY - visibleRect.minY
    }

    override func draw(_ dirtyRect: NSRect) {
        guard pageColumns > 0 else {
            super.draw(dirtyRect)
            return
        }
        backgroundColor.setFill()
        NSBezierPath(rect: dirtyRect).fill()
        guard
              let layoutManager,
              !pageColumnFrames.isEmpty else { return }
        for index in 0..<min(layoutManager.textContainers.count, pageColumnFrames.count) {
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
            scrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let direction = ReaderKeyNavigation.pageDirection(for: event),
           let scrollView = enclosingScrollView as? ReaderScrollView {
            scrollView.handleKeyboardNavigate(direction)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if ReaderKeyNavigation.isFind(event) { return false }
        return super.performKeyEquivalent(with: event)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        if let offset = pageOffset(forCharacter: range.location),
           let scrollView = enclosingScrollView as? ReaderScrollView {
            scrollView.scroll(to: offset, animated: false)
            return
        }
        super.scrollRangeToVisible(range)
    }

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        // 分页模式下原生插入点滚动会把 clip view 带离页边界, 进入书本时出现微小偏移.
        if pageColumns > 0 { return true }
        return super.scrollToVisible(rect)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard pageColumns > 0 else { return super.hitTest(point) }
        let localPoint = convert(point, from: superview)
        guard !isHiddenOrHasHiddenAncestor,
              visibleRect.contains(localPoint) else { return nil }
        // 原生命中仅覆盖第一个文本容器, 分页绘制的其余栏和空白也需要接收事件.
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {
        onSpeechInteraction?(true)
        defer {
            if !isSelectingPageText, pendingImageHit == nil { onSpeechInteraction?(false) }
        }
        if event.clickCount == 1, let hit = imageHit(at: event) {
            guard allowsImagePreview else { return }
            pendingImageHit = hit
            return
        }
        if pageColumns > 0, event.clickCount == 1,
           let scrollView = enclosingScrollView as? ReaderScrollView {
            let point = convert(event.locationInWindow, from: nil)
            let edge = min(44, textContainerInset.width)
            if point.x < edge || point.x > bounds.width - edge {
                window?.makeFirstResponder(self)
                scrollView.turnPage(direction: point.x < edge ? -1 : 1)
                return
            }
        }
        // 单栏和双栏都按分页容器绘制, 选择位置也必须使用对应容器的坐标.
        guard pageColumns > 0 else {
            if event.clickCount == 1, event.type == .leftMouseDown {
                let location = characterLocation(for: event)
                if let annotation = annotationAtLocation?(location), annotation.kind == "note" {
                    onAnnotationClick?(annotation)
                    return
                }
            }
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 1, let link = link(at: event) {
            onLink?(link)
            return
        }
        if event.clickCount == 1 {
            let location = characterLocation(for: event)
            if let annotation = annotationAtLocation?(location), annotation.kind == "note" {
                onAnnotationClick?(annotation)
                return
            }
        }
        guard event.clickCount == 1,
              event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }
        let location = characterLocation(for: event)
        selectionAnchorLocation = location
        isSelectingPageText = true
        window?.makeFirstResponder(self)
        updatePageSelection(NSRange(location: location, length: 0))
    }

    override func mouseDragged(with event: NSEvent) {
        onSpeechInteraction?(true)
        if pendingImageHit != nil {
            return
        }
        guard pageColumns > 0,
              isSelectingPageText,
              let anchor = selectionAnchorLocation else {
            super.mouseDragged(with: event)
            return
        }
        let location = characterLocation(for: event)
        let range = NSRange(
            location: min(anchor, location),
            length: abs(location - anchor)
        )
        updatePageSelection(range)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            onSpeechInteraction?(false)
        }
        if let pending = pendingImageHit {
            pendingImageHit = nil
            if allowsImagePreview, pending.rect.contains(event.locationInWindow) {
                onImageClick?(pending.image, pending.rect)
            }
            return
        }
        guard pageColumns > 0,
              isSelectingPageText else {
            super.mouseUp(with: event)
            return
        }
        let location = characterLocation(for: event)
        if let anchor = selectionAnchorLocation {
            updatePageSelection(NSRange(
                location: min(anchor, location),
                length: abs(location - anchor)
            ))
        }
        selectionAnchorLocation = nil
        isSelectingPageText = false
    }

    override func resetCursorRects() {
        // 不调用 super, 避免 NSTextView 默认把整片文本区域都设成 I-beam.
        visitDeclaredCursorRects { rect, cursor in
            self.addCursorRect(rect, cursor: cursor)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        // 不调用 super, 跳过 NSTextView 默认 I-beam.
        applyDeclaredCursor(at: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // 不调用 super, 跳过 NSTextView 默认 I-beam.
        applyDeclaredCursor(at: event)
    }

    override func mouseEntered(with event: NSEvent) {
        // 不调用 super, 跳过 NSTextView 默认 I-beam.
        applyDeclaredCursor(at: event)
    }

    private func applyDeclaredCursor(at event: NSEvent) {
        let hitView = window?.contentView?.hitTest(event.locationInWindow)
        guard hitView === self || (hitView?.isDescendant(of: self) ?? false) else { return }

        let point = convert(event.locationInWindow, from: nil)
        var cursor = NSCursor.arrow
        visitDeclaredCursorRects { rect, declared in
            if rect.contains(point) {
                cursor = declared
            }
        }
        cursor.set()
    }

    private func visitDeclaredCursorRects(_ visit: @escaping (NSRect, NSCursor) -> Void) {
        visit(visibleRect, .arrow)
        guard let layoutManager, let textStorage else { return }
        guard !visibleRect.isEmpty else { return }

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

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
                _, usedRect, container, _, _ in
                guard container === textContainer, !usedRect.isEmpty else { return }
                let lineRect = usedRect.offsetBy(dx: origin.x, dy: origin.y).intersection(self.visibleRect)
                guard !lineRect.isEmpty else { return }
                visit(lineRect, .iBeam)
            }

            guard allowsImagePreview else { continue }
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            textStorage.enumerateAttribute(.attachment, in: characterRange) {
                value, range, _ in
                guard value is NSTextAttachment else { return }
                let attachmentGlyphRange = layoutManager.glyphRange(
                    forCharacterRange: range,
                    actualCharacterRange: nil
                )
                let attachmentRect = layoutManager.boundingRect(
                    forGlyphRange: attachmentGlyphRange,
                    in: textContainer
                )
                guard !attachmentRect.isEmpty else { return }
                let viewRect = attachmentRect.offsetBy(dx: origin.x, dy: origin.y).intersection(self.visibleRect)
                guard !viewRect.isEmpty else { return }
                visit(viewRect, .pointingHand)
            }
        }
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

    private func imageHit(at event: NSEvent) -> (image: NSImage, rect: NSRect)? {
        guard let layoutManager, let textStorage else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let (textContainer, origin) = textContainerContext(at: point) else { return nil }
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let containerGlyphRange = layoutManager.glyphRange(for: textContainer)
        guard containerGlyphRange.length > 0,
              glyphIndex >= containerGlyphRange.location,
              glyphIndex < NSMaxRange(containerGlyphRange) else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.contains(containerPoint) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length,
              let attachment = textStorage.attribute(.attachment, at: characterIndex, effectiveRange: nil) as? NSTextAttachment else {
            return nil
        }
        guard let image = attachment.image else { return nil }
        let viewRect = glyphRect.offsetBy(dx: origin.x, dy: origin.y)
        return (image, convert(viewRect, to: nil))
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        if let hit = imageHit(at: event) {
            let menu = NSMenu(title: "图片")
            menu.autoenablesItems = false
            let item = menuItem(title: "导出图片...", symbol: "square.and.arrow.up", action: #selector(exportImage(_:)))
            item.representedObject = hit.image
            menu.addItem(item)
            return menu
        }
        let range = validSelectionRange() ?? NSRange(location: 0, length: 0)
        let clickedLocation = characterLocation(for: event)
        contextLocation = range.length > 0 ? range.location : clickedLocation
        let annotation = annotationAtLocation?(clickedLocation)
            ?? (range.length > 0 ? annotationAtLocation?(range.location) : nil)
        contextAnnotationID = annotation?.id
        let menu = NSMenu(title: "阅读")
        menu.autoenablesItems = false

        if range.length > 0 {
            menu.addItem(menuItem(title: "高亮", symbol: "highlighter", action: #selector(highlightSelection)))
            menu.addItem(menuItem(title: "添加笔记", symbol: "note.text", action: #selector(addNote)))
        }
        if let annotation {
            menu.addItem(menuItem(
                title: annotation.kind == "note" ? "删除笔记" : "取消高亮",
                symbol: annotation.kind == "note" ? "trash" : "highlighter.slash",
                action: #selector(removeAnnotation)
            ))
        }
        menu.addItem(menuItem(title: "从此处开始朗读", symbol: "speaker.wave.2", action: #selector(speakFromSelection)))
        if range.length > 0 {
            menu.addItem(.separator())
            menu.addItem(menuItem(title: "拷贝", symbol: "doc.on.doc", action: #selector(copySelection)))
        }
        return menu
    }

    @objc private func exportImage(_ sender: NSMenuItem) {
        guard let image = sender.representedObject as? NSImage else { return }
        ReaderImageExporter.export(image, from: window)
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

    @objc private func removeAnnotation() {
        guard let id = contextAnnotationID else { return }
        onRemoveAnnotation?(id)
        contextAnnotationID = nil
    }

    private func updateReadingInsets(for width: CGFloat) {
        let centeredInset = (width - preferredReadingWidth) / 2
        let horizontalInset = max(minimumHorizontalInset, centeredInset)
        let nextInset = NSSize(width: horizontalInset, height: verticalInset)
        if textContainerInset != nextInset {
            textContainerInset = nextInset
        }
    }

    private func updatePageSelection(_ range: NSRange) {
        let length = (string as NSString).length
        let clampedLocation = min(max(range.location, 0), length)
        let clampedLength = min(max(range.length, 0), length - clampedLocation)
        setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
        needsDisplay = true
    }

    private func updatePageLayout(minimumHeight: CGFloat) {
        guard !isUpdatingPageLayout, pageColumns > 0,
              let layoutManager, let textStorage else { return }
        isUpdatingPageLayout = true
        defer { isUpdatingPageLayout = false }
        pageViewportHeight = max(1, minimumHeight)
        let layout = ReaderPageLayout(
            layoutManager: layoutManager, storage: textStorage,
            viewport: NSSize(width: bounds.width, height: pageViewportHeight),
            columns: pageColumns,
            horizontalInset: textContainerInset.width, verticalInset: verticalInset
        )
        pageColumnFrames = layout.frames
        pageCount = layout.pageCount
        if abs(frame.height - layout.documentHeight) > 0.5 {
            super.setFrameSize(NSSize(width: frame.width, height: layout.documentHeight))
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
        let color = NSColor.controlAccentColor.withAlphaComponent(0.28)
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
        if pageColumns > 0 {
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
