import AppKit
import OSLog
import SwiftUI

struct NativeReaderView: NSViewRepresentable {
    let book: BookSummary
    @Binding var sectionIndex: Int
    let theme: ReadingTheme
    let fontSize: Double
    let lineHeight: Double
    let margin: Double
    let annotations: [ReaderAnnotation]
    @ObservedObject var controller: ReaderController
    let onProgress: (Double) -> Void
    let onBoundary: (Int) -> Void
    let onSpeakingChanged: (Bool) -> Void
    let onAnnotation: (String, String, NSRange) -> Void
    let onNoteRequest: (String, NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let initialSize = NSSize(width: 900, height: 680)
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: initialSize))
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder

        let textView = ReaderTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
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
            theme: theme,
            fontSize: fontSize,
            lineHeight: lineHeight,
            margin: margin,
            annotations: annotations,
            onProgress: onProgress,
            onBoundary: onBoundary,
            onSpeakingChanged: onSpeakingChanged,
            onAnnotation: onAnnotation,
            onNoteRequest: onNoteRequest
        )
        context.coordinator.loadSectionIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(
            book: book,
            sectionIndex: sectionIndex,
            theme: theme,
            fontSize: fontSize,
            lineHeight: lineHeight,
            margin: margin,
            annotations: annotations,
            onProgress: onProgress,
            onBoundary: onBoundary,
            onSpeakingChanged: onSpeakingChanged,
            onAnnotation: onAnnotation,
            onNoteRequest: onNoteRequest
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
        private var currentSectionIndex = -1
        private var settings = Settings(theme: .focus, fontSize: 18, lineHeight: 1.7, margin: 56)
        private var loadedSettings: Settings?
        private var annotations: [ReaderAnnotation] = []
        private var renderedAnnotationRanges: [(range: NSRange, kind: String)] = []
        private var speechRange: NSRange?
        private var speechBaseLocation = 0
        private var onProgress: (Double) -> Void = { _ in }
        private var onBoundary: (Int) -> Void = { _ in }
        private var onSpeakingChanged: (Bool) -> Void = { _ in }
        private var onAnnotation: (String, String, NSRange) -> Void = { _, _, _ in }
        private var onNoteRequest: (String, NSRange) -> Void = { _, _ in }
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
            textView.onHighlight = { [weak self] text, range in
                self?.onAnnotation(text, "highlight", range)
            }
            textView.onNote = { [weak self] text, range in
                self?.onNoteRequest(text, range)
            }
            textView.onSpeak = { [weak self] location in
                self?.startSpeech(at: location)
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateDocumentLayout()
                    self?.reportProgress()
                }
            }
        }

        func update(
            book: BookSummary,
            sectionIndex: Int,
            theme: ReadingTheme,
            fontSize: Double,
            lineHeight: Double,
            margin: Double,
            annotations: [ReaderAnnotation],
            onProgress: @escaping (Double) -> Void,
            onBoundary: @escaping (Int) -> Void,
            onSpeakingChanged: @escaping (Bool) -> Void,
            onAnnotation: @escaping (String, String, NSRange) -> Void,
            onNoteRequest: @escaping (String, NSRange) -> Void
        ) {
            self.book = book
            requestedSectionIndex = sectionIndex
            settings = Settings(theme: theme, fontSize: fontSize, lineHeight: lineHeight, margin: margin)
            let annotationsChanged = self.annotations != annotations
            self.annotations = annotations
            self.onProgress = onProgress
            self.onBoundary = onBoundary
            self.onSpeakingChanged = onSpeakingChanged
            self.onAnnotation = onAnnotation
            self.onNoteRequest = onNoteRequest
            if annotationsChanged {
                applyAnnotations()
            }
        }

        func loadSectionIfNeeded() {
            guard currentSectionIndex != requestedSectionIndex || loadedSettings != settings else { return }
            guard let book, let textView, let scrollView else { return }
            let previousSectionIndex = currentSectionIndex
            stopSpeech()
            let appearance = NativeReaderAppearance(theme: settings.theme)
            do {
                let attributedText = try loader.load(
                    book: book,
                    sectionIndex: requestedSectionIndex,
                    fontSize: settings.fontSize,
                    lineHeight: settings.lineHeight,
                    foreground: appearance.foreground
                )
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
                loadedSettings = settings
                applyAnnotations()
                updateDocumentLayout()
                if previousSectionIndex >= 0, requestedSectionIndex < previousSectionIndex {
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
            stopSpeech()
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = nil
            textView?.onHighlight = nil
            textView?.onNote = nil
            textView?.onSpeak = nil
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
                self?.onSpeakingChanged(speaking)
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
            onSpeakingChanged(false)
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

        @discardableResult
        private func updateDocumentLayout() -> CGFloat {
            guard let scrollView, let textView else { return 0 }
            textView.updateDocumentHeight(minimumHeight: scrollView.contentSize.height)
            return max(scrollView.contentSize.height, textView.frame.height)
        }

        private func maximumScrollOffset() -> CGFloat {
            guard let scrollView else { return 0 }
            return max(0, updateDocumentLayout() - scrollView.contentView.bounds.height)
        }

        private func scrollPage(direction: Int) {
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            let current = clipView.bounds.origin.y
            let maximum = maximumScrollOffset()
            if direction > 0, current >= maximum - 2 {
                onBoundary(1)
                return
            }
            if direction < 0, current <= 2 {
                onBoundary(-1)
                return
            }
            let amount = max(240, clipView.bounds.height * 0.88)
            let next = min(maximum, max(0, current + CGFloat(direction) * amount))
            clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: next))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func scrollToEnd() {
            guard let scrollView else { return }
            let maximum = maximumScrollOffset()
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximum))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func reportProgress() {
            guard let scrollView else { return }
            let maximum = maximumScrollOffset()
            let fraction = maximum > 0 ? scrollView.contentView.bounds.origin.y / maximum : 0
            onProgress(min(1, max(0, fraction)))
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
