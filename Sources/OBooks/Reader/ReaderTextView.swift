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
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = max(minimumHeight, ceil(usedRect.maxY + verticalInset * 2))
        guard abs(frame.height - requiredHeight) > 0.5 else { return }
        super.setFrameSize(NSSize(width: frame.width, height: requiredHeight))
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        updateReadingInsets(for: newSize.width)
        if widthChanged {
            updateDocumentHeight(minimumHeight: superview?.bounds.height ?? 0)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if let scrollView = enclosingScrollView as? ReaderScrollView {
            scrollView.notifyUserScroll()
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
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        guard let layoutManager, let textContainer, let textStorage else { return }
        guard !visibleRect.isEmpty else { return }
        let origin = textContainerOrigin
        let visibleContainerRect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

        let string = textStorage.string as NSString
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
        guard let layoutManager, let textContainer, let textStorage else { return }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
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
        guard let layoutManager, let textContainer else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
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

    private func validSelectionRange() -> NSRange? {
        let range = selectedRange()
        let length = (string as NSString).length
        guard range.location != NSNotFound,
              range.location <= length,
              range.length <= length - range.location else { return nil }
        return range
    }

    private func characterLocation(for event: NSEvent) -> Int {
        guard let layoutManager, let textContainer else { return selectedRange().location }
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return (string as NSString).length }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    private func menuItem(title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.isEnabled = true
        return item
    }
}
