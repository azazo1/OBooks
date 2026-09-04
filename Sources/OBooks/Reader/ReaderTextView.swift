import AppKit

@MainActor
final class ReaderTextView: NSTextView {
    var onHighlight: ((String, NSRange) -> Void)?
    var onNote: ((String, NSRange) -> Void)?
    var onSpeak: ((Int) -> Void)?
    var preferredReadingWidth: CGFloat = 820
    var minimumHorizontalInset: CGFloat = 34
    private var verticalInset: CGFloat = 52
    private var contextLocation = 0

    func setReadingInsets(horizontal: CGFloat, vertical: CGFloat) {
        minimumHorizontalInset = horizontal
        verticalInset = vertical
        updateReadingInsets(for: bounds.width)
    }

    func updateDocumentHeight(minimumHeight: CGFloat) {
        guard let layoutManager, let textContainer, bounds.width > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = max(minimumHeight, ceil(usedRect.maxY + verticalInset * 2))
        guard abs(frame.height - requiredHeight) > 0.5 else { return }
        super.setFrameSize(NSSize(width: frame.width, height: requiredHeight))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        updateReadingInsets(for: newSize.width)
        if widthChanged {
            updateDocumentHeight(minimumHeight: superview?.bounds.height ?? 0)
        }
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
