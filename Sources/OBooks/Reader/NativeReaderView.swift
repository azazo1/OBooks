import AppKit
import OSLog
import SwiftUI

struct NativeReaderView: NSViewRepresentable {
    let book: BookSummary
    @Binding var sectionIndex: Int
    @Binding var pendingAnchor: String?
    @Binding var pendingPosition: ReadingPosition?
    let theme: ReadingTheme
    let fontSize: Double
    let lineHeight: Double
    let margin: Double
    let annotations: [ReaderAnnotation]
    @ObservedObject var controller: ReaderController
    let onProgress: (Double, ReadingPosition) -> Void
    let onBoundary: (Int) -> Void
    let onSpeakingChanged: (Bool) -> Void
    let onAnnotation: (String, String, NSRange) -> Void
    let onNoteRequest: (String, NSRange) -> Void
    let onNavigate: (Int, String?) -> Void
    let onAnchorConsumed: () -> Void
    let onPositionConsumed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let initialSize = NSSize(width: 900, height: 680)
        let scrollView = ReaderScrollView(frame: NSRect(origin: .zero, size: initialSize))
        scrollView.wantsLayer = true
        scrollView.contentView.wantsLayer = true
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder

        let textView = ReaderTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.wantsLayer = true
        textView.layer?.drawsAsynchronously = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesFindPanel = true
        textView.importsGraphics = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.preferredReadingWidth = 820
        textView.minimumHorizontalInset = 34
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        context.coordinator.update(
            book: book,
            sectionIndex: sectionIndex,
            pendingAnchor: pendingAnchor,
            pendingPosition: pendingPosition,
            theme: theme,
            fontSize: fontSize,
            lineHeight: lineHeight,
            margin: margin,
            annotations: annotations,
            onProgress: onProgress,
            onBoundary: onBoundary,
            onSpeakingChanged: onSpeakingChanged,
            onAnnotation: onAnnotation,
            onNoteRequest: onNoteRequest,
            onNavigate: onNavigate,
            onAnchorConsumed: onAnchorConsumed,
            onPositionConsumed: onPositionConsumed
        )
        context.coordinator.loadSectionIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(
            book: book,
            sectionIndex: sectionIndex,
            pendingAnchor: pendingAnchor,
            pendingPosition: pendingPosition,
            theme: theme,
            fontSize: fontSize,
            lineHeight: lineHeight,
            margin: margin,
            annotations: annotations,
            onProgress: onProgress,
            onBoundary: onBoundary,
            onSpeakingChanged: onSpeakingChanged,
            onAnnotation: onAnnotation,
            onNoteRequest: onNoteRequest,
            onNavigate: onNavigate,
            onAnchorConsumed: onAnchorConsumed,
            onPositionConsumed: onPositionConsumed
        )
        coordinator.loadSectionIfNeeded()
        if coordinator.lastCommandID != controller.command?.id, let command = controller.command {
            coordinator.execute(command.action)
            coordinator.lastCommandID = command.id
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject {
        private struct Settings: Equatable {
            let theme: ReadingTheme
            let fontSize: Double
            let lineHeight: Double
            let margin: Double
        }

        private let loader = NativeChapterLoader()
        private let speech = SpeechService()
        private let logger = Logger(subsystem: "com.obooks.app", category: "reader.native")
        private weak var scrollView: NSScrollView?
        private weak var textView: ReaderTextView?
        private var scrollObserver: NSObjectProtocol?
        private var book: BookSummary?
        private var requestedSectionIndex = 0
        private var pendingAnchor: String?
        private var pendingPosition: ReadingPosition?
        private var currentSectionIndex = -1
        private var anchors: [String: Int] = [:]
        private var settings = Settings(theme: .focus, fontSize: 18, lineHeight: 1.7, margin: 56)
        private var loadedSettings: Settings?
        private var annotations: [ReaderAnnotation] = []
        private var renderedAnnotationRanges: [(range: NSRange, kind: String)] = []
        private var speechRange: NSRange?
        private var speechBaseLocation = 0
        private var onProgress: (Double, ReadingPosition) -> Void = { _, _ in }
        private var onBoundary: (Int) -> Void = { _ in }
        private var onSpeakingChanged: (Bool) -> Void = { _ in }
        private var onAnnotation: (String, String, NSRange) -> Void = { _, _, _ in }
        private var onNoteRequest: (String, NSRange) -> Void = { _, _ in }
        private var onNavigate: (Int, String?) -> Void = { _, _ in }
        private var onAnchorConsumed: () -> Void = {}
        private var onPositionConsumed: () -> Void = {}
        private var pendingProgress: Double?
        private var pendingReadingPosition: ReadingPosition?
        private var progressCallbackScheduled = false
        private var isTornDown = false
        var lastCommandID: UUID?

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        func attach(scrollView: NSScrollView, textView: ReaderTextView) {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            self.scrollView = scrollView
            self.textView = textView
            isTornDown = false
            textView.onHighlight = { [weak self] text, range in
                self?.onAnnotation(text, "highlight", range)
            }
            textView.onNote = { [weak self] text, range in
                self?.onNoteRequest(text, range)
            }
            textView.onSpeak = { [weak self] location in
                self?.startSpeech(at: location)
            }
            textView.onLink = { [weak self] url in
                self?.openLink(url)
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportProgress()
                }
            }
        }

        func update(
            book: BookSummary,
            sectionIndex: Int,
            pendingAnchor: String?,
            pendingPosition: ReadingPosition?,
            theme: ReadingTheme,
            fontSize: Double,
            lineHeight: Double,
            margin: Double,
            annotations: [ReaderAnnotation],
            onProgress: @escaping (Double, ReadingPosition) -> Void,
            onBoundary: @escaping (Int) -> Void,
            onSpeakingChanged: @escaping (Bool) -> Void,
            onAnnotation: @escaping (String, String, NSRange) -> Void,
            onNoteRequest: @escaping (String, NSRange) -> Void,
            onNavigate: @escaping (Int, String?) -> Void,
            onAnchorConsumed: @escaping () -> Void,
            onPositionConsumed: @escaping () -> Void
        ) {
            self.book = book
            requestedSectionIndex = sectionIndex
            let anchorChanged = self.pendingAnchor != pendingAnchor
            self.pendingAnchor = pendingAnchor
            let positionChanged = self.pendingPosition != pendingPosition
            self.pendingPosition = pendingPosition
            settings = Settings(theme: theme, fontSize: fontSize, lineHeight: lineHeight, margin: margin)
            let annotationsChanged = self.annotations != annotations
            self.annotations = annotations
            self.onProgress = onProgress
            self.onBoundary = onBoundary
            self.onSpeakingChanged = onSpeakingChanged
            self.onAnnotation = onAnnotation
            self.onNoteRequest = onNoteRequest
            self.onNavigate = onNavigate
            self.onAnchorConsumed = onAnchorConsumed
            self.onPositionConsumed = onPositionConsumed
            if annotationsChanged {
                applyAnnotations()
            }
            if anchorChanged, currentSectionIndex == sectionIndex, let pendingAnchor, let location = anchors[pendingAnchor] {
                scrollToCharacter(location, animated: true)
                consumePendingAnchor()
            }
            if positionChanged,
               currentSectionIndex == sectionIndex,
               let pendingPosition,
               isPositionForCurrentSection(pendingPosition) {
                scrollToCharacter(pendingPosition.characterOffset, animated: false)
                consumePendingPosition()
            }
        }

        func loadSectionIfNeeded() {
            guard currentSectionIndex != requestedSectionIndex || loadedSettings != settings else { return }
            guard let book, let textView, let scrollView else { return }
            let previousSectionIndex = currentSectionIndex
            stopSpeech()
            let appearance = NativeReaderAppearance(theme: settings.theme)
            do {
                let document = try loader.loadDocument(
                    book: book,
                    sectionIndex: requestedSectionIndex,
                    fontSize: settings.fontSize,
                    lineHeight: settings.lineHeight,
                    foreground: appearance.foreground
                )
                let attributedText = document.attributedText
                textView.backgroundColor = appearance.background
                textView.insertionPointColor = appearance.accent
                textView.selectedTextAttributes = [
                    .backgroundColor: appearance.selection,
                    .foregroundColor: appearance.foreground
                ]
                textView.setReadingInsets(
                    horizontal: max(34, settings.margin),
                    vertical: max(52, settings.margin)
                )
                renderedAnnotationRanges.removeAll()
                textView.textStorage?.setAttributedString(attributedText)
                scrollView.backgroundColor = appearance.background
                currentSectionIndex = requestedSectionIndex
                anchors = document.anchors
                loadedSettings = settings
                applyAnnotations()
                updateDocumentLayout()
                if let pendingAnchor, let location = anchors[pendingAnchor] {
                    scrollToCharacter(location, animated: false)
                    consumePendingAnchor()
                } else if pendingAnchor != nil {
                    consumePendingAnchor()
                } else if let pendingPosition {
                    if isPositionForCurrentSection(pendingPosition) {
                        scrollToCharacter(pendingPosition.characterOffset, animated: false)
                    }
                    consumePendingPosition()
                } else if previousSectionIndex >= 0, requestedSectionIndex < previousSectionIndex {
                    scrollToEnd()
                } else {
                    scrollView.contentView.scroll(to: .zero)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
                reportProgress()
            } catch {
                logger.error("加载原生章节失败: section=\(self.requestedSectionIndex), error=\(error.localizedDescription, privacy: .public)")
                textView.string = "无法显示这一章\n\n\(error.localizedDescription)"
                currentSectionIndex = requestedSectionIndex
                loadedSettings = settings
            }
        }

        func execute(_ action: ReaderAction) {
            switch action {
            case .nextPage:
                scrollPage(direction: 1)
            case .previousPage:
                scrollPage(direction: -1)
            case .seek(let fraction, let animated):
                seek(to: fraction, animated: animated)
            case .toggleSpeech:
                if speech.isSpeaking {
                    stopSpeech()
                } else {
                    startSpeech(at: firstVisibleCharacterLocation())
                }
            case .stopSpeech:
                stopSpeech()
            }
        }

        func teardown() {
            isTornDown = true
            (scrollView as? ReaderScrollView)?.prepareForProgrammaticScroll()
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = nil
            onProgress = { _, _ in }
            onBoundary = { _ in }
            onSpeakingChanged = { _ in }
            onAnnotation = { _, _, _ in }
            onNoteRequest = { _, _ in }
            onNavigate = { _, _ in }
            onAnchorConsumed = {}
            onPositionConsumed = {}
            pendingProgress = nil
            pendingReadingPosition = nil
            speech.onRange = nil
            speech.onFinished = nil
            speech.onStateChanged = nil
            speech.stop()
            speechRange = nil
            renderedAnnotationRanges.removeAll()
            textView?.onHighlight = nil
            textView?.onNote = nil
            textView?.onSpeak = nil
            textView?.onLink = nil
        }

        private func consumePendingAnchor() {
            pendingAnchor = nil
            let callback = onAnchorConsumed
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown else { return }
                callback()
            }
        }

        private func consumePendingPosition() {
            pendingPosition = nil
            let callback = onPositionConsumed
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown else { return }
                callback()
            }
        }

        private func isPositionForCurrentSection(_ position: ReadingPosition) -> Bool {
            guard let book, book.spine.indices.contains(currentSectionIndex) else { return false }
            return spineIdentity(book.spine[currentSectionIndex]) == position.spineID
        }

        private func spineIdentity(_ item: EPUBSpineItem) -> String {
            item.id.isEmpty ? item.href : item.id
        }

        private func openLink(_ url: URL) {
            guard let book else { return }
            let rootURL = book.folderURL.standardizedFileURL
            let candidate = url.standardizedFileURL
            guard candidate.path.hasPrefix(rootURL.path + "/") else {
                NSWorkspace.shared.open(url)
                return
            }
            let relativePath = String(candidate.path.dropFirst(rootURL.path.count + 1))
            guard let sectionIndex = book.spine.firstIndex(where: { $0.href == relativePath }) else {
                return
            }
            onNavigate(sectionIndex, url.fragment?.removingPercentEncoding)
        }

        private func scrollToCharacter(_ location: Int, animated: Bool) {
            guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
            let length = (textView.string as NSString).length
            let clampedLocation = min(max(location, 0), length)
            let glyphIndex = clampedLocation < length ? layoutManager.glyphIndexForCharacter(at: clampedLocation) : layoutManager.numberOfGlyphs
            let rect: NSRect
            if glyphIndex < layoutManager.numberOfGlyphs {
                rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            } else {
                rect = layoutManager.usedRect(for: textContainer)
            }
            let y = max(0, rect.minY + textView.textContainerOrigin.y - textView.textContainerInset.height)
            if animated {
                (scrollView as? ReaderScrollView)?.scroll(to: y, animated: true)
            } else if let scrollView {
                (scrollView as? ReaderScrollView)?.prepareForProgrammaticScroll()
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        private func startSpeech(at location: Int) {
            guard let textView else { return }
            let fullText = textView.string as NSString
            let start = min(max(location, 0), fullText.length)
            guard start < fullText.length else { return }
            speechBaseLocation = start
            speech.onRange = { [weak self] range in
                guard let self else { return }
                self.showSpeechRange(NSRange(location: self.speechBaseLocation + range.location, length: range.length))
            }
            speech.onStateChanged = { [weak self] speaking in
                self?.notifySpeakingChanged(speaking)
                if !speaking {
                    self?.clearSpeechRange()
                }
            }
            speech.onFinished = { [weak self] in
                self?.clearSpeechRange()
            }
            speech.speak(text: fullText.substring(from: start))
        }

        private func stopSpeech() {
            speech.onRange = nil
            speech.onFinished = nil
            speech.onStateChanged = nil
            speech.stop()
            notifySpeakingChanged(false)
            clearSpeechRange()
        }

        private func showSpeechRange(_ range: NSRange) {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            clearSpeechRange()
            let validRange = NSIntersectionRange(range, NSRange(location: 0, length: textView.string.utf16.count))
            guard validRange.length > 0 else { return }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NativeReaderAppearance(theme: settings.theme).speechHighlight,
                forCharacterRange: validRange
            )
            speechRange = validRange
            textView.scrollRangeToVisible(validRange)
        }

        private func clearSpeechRange() {
            guard let range = speechRange, let layoutManager = textView?.layoutManager else { return }
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            speechRange = nil
            applyAnnotations()
        }

        private func applyAnnotations() {
            guard let textView, let layoutManager = textView.layoutManager, currentSectionIndex >= 0 else { return }
            let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
            for rendered in renderedAnnotationRanges {
                let range = NSIntersectionRange(rendered.range, fullRange)
                guard range.length > 0 else { continue }
                if rendered.kind == "note" {
                    layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
                    layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
                } else {
                    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                }
            }
            renderedAnnotationRanges.removeAll()

            let appearance = NativeReaderAppearance(theme: settings.theme)
            for annotation in annotations where annotation.sectionIndex == currentSectionIndex {
                let range = NSIntersectionRange(annotation.range, fullRange)
                guard range.length > 0 else { continue }
                if annotation.kind == "note" {
                    layoutManager.addTemporaryAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: appearance.accent
                    ], forCharacterRange: range)
                } else {
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: appearance.userHighlight,
                        forCharacterRange: range
                    )
                }
                renderedAnnotationRanges.append((range, annotation.kind))
            }
        }

        private func notifyProgress(_ value: Double, position: ReadingPosition) {
            pendingProgress = value
            pendingReadingPosition = position
            guard !progressCallbackScheduled else { return }
            progressCallbackScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.progressCallbackScheduled = false
                guard !self.isTornDown,
                      let value = self.pendingProgress,
                      let position = self.pendingReadingPosition else {
                    self.pendingProgress = nil
                    self.pendingReadingPosition = nil
                    return
                }
                self.pendingProgress = nil
                self.pendingReadingPosition = nil
                self.onProgress(value, position)
            }
        }

        private func notifyBoundary(_ direction: Int) {
            let callback = onBoundary
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown else { return }
                callback(direction)
            }
        }

        private func notifySpeakingChanged(_ value: Bool) {
            let callback = onSpeakingChanged
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown else { return }
                callback(value)
            }
        }

        @discardableResult
        private func updateDocumentLayout() -> CGFloat {
            guard let scrollView, let textView else { return 0 }
            textView.updateDocumentHeight(minimumHeight: scrollView.contentSize.height)
            return max(scrollView.contentSize.height, textView.frame.height)
        }

        private func maximumScrollOffset() -> CGFloat {
            guard let scrollView, let textView else { return 0 }
            return max(0, textView.frame.height - scrollView.contentView.bounds.height)
        }

        private func scrollPage(direction: Int) {
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            let current = clipView.bounds.origin.y
            let maximum = maximumScrollOffset()
            if direction > 0, current >= maximum - 2 {
                notifyBoundary(1)
                return
            }
            if direction < 0, current <= 2 {
                notifyBoundary(-1)
                return
            }
            let amount = max(240, clipView.bounds.height * 0.88)
            let next = min(maximum, max(0, current + CGFloat(direction) * amount))
            scroll(to: next, animated: true)
        }

        private func seek(to fraction: Double, animated: Bool) {
            let normalized = min(max(fraction, 0), 1)
            scroll(to: CGFloat(normalized) * maximumScrollOffset(), animated: animated)
        }

        private func scroll(to offset: CGFloat, animated: Bool) {
            guard let scrollView else { return }
            if let readerScrollView = scrollView as? ReaderScrollView {
                readerScrollView.scroll(to: offset, animated: animated)
                return
            }
            let clipView = scrollView.contentView
            clipView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func scrollToEnd() {
            guard let scrollView else { return }
            let maximum = maximumScrollOffset()
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximum))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func reportProgress() {
            guard let scrollView, let book, book.spine.indices.contains(currentSectionIndex) else { return }
            let maximum = maximumScrollOffset()
            let fraction = maximum > 0 ? scrollView.contentView.bounds.origin.y / maximum : 0
            let position = ReadingPosition(
                spineID: spineIdentity(book.spine[currentSectionIndex]),
                characterOffset: firstVisibleCharacterLocation()
            )
            notifyProgress(min(1, max(0, fraction)), position: position)
        }

        private func firstVisibleCharacterLocation() -> Int {
            guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return 0 }
            let origin = textView.textContainerOrigin
            var visibleRect = textView.visibleRect
            visibleRect.origin.x -= origin.x
            visibleRect.origin.y -= origin.y
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            guard glyphRange.length > 0,
                  glyphRange.location != NSNotFound,
                  glyphRange.location < layoutManager.numberOfGlyphs else { return 0 }
            return layoutManager.characterIndexForGlyph(at: glyphRange.location)
        }
    }
}
