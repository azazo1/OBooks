import AppKit
import OSLog
import SwiftUI

struct NativeReaderView: NSViewRepresentable {
    let book: BookSummary
    @Binding var sectionIndex: Int
    @Binding var pendingAnchor: String?
    @Binding var pendingPosition: ReadingPosition?
    @Binding var pendingPositionAnimated: Bool
    @Binding var pendingSearchReveal: ReaderSearchReveal?
    let theme: ReadingTheme
    let flow: ReaderFlowMode
    let fontSize: Double
    let lineHeight: Double
    let margin: Double
    let annotations: [ReaderAnnotation]
    @ObservedObject var controller: ReaderController
    var speechOverlayRect: NSRect = .zero
    let onProgress: (Double, ReadingPosition) -> Void
    var onTOCSelection: (UUID?) -> Void = { _ in }
    let onPageInfo: (Int, Int) -> Void
    let onBoundary: (Int) -> Void
    let onSpeakingChanged: (Bool) -> Void
    let onAnnotation: (String, String, NSRange) -> Void
    let onNoteRequest: (String, NSRange) -> Void
    var onAnnotationClick: (ReaderAnnotation) -> Void = { _ in }
    var onAnnotationAtSection: (String, String, Int, NSRange) -> Void = { _, _, _, _ in }
    var onRemoveAnnotation: (UUID) -> Void = { _ in }
    var onImageClick: (NSImage, NSRect) -> Void = { _, _ in }
    var onFind: () -> Void = {}
    let onNavigate: (Int, String?) -> Void
    let onAnchorConsumed: () -> Void
    let onPositionConsumed: () -> Void
    var onSearchConsumed: () -> Void = {}
    var onContentReady: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(speech: controller.speech)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let initialSize = AppWindowConfiguration.readerWindowSize
        let scrollView = ReaderScrollView(frame: NSRect(origin: .zero, size: initialSize))
        scrollView.wantsLayer = true
        scrollView.layer?.masksToBounds = true
        scrollView.contentView.wantsLayer = true
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = flow.scrollScope != nil
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()

        let textView = ReaderTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.wantsLayer = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesFindPanel = false
        textView.importsGraphics = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.preferredReadingWidth = 1150
        textView.minimumHorizontalInset = 34
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        context.coordinator.onFind = onFind
        context.coordinator.update(
            book: book,
            sectionIndex: sectionIndex,
            pendingAnchor: pendingAnchor,
            pendingPosition: pendingPosition,
            pendingPositionAnimated: pendingPositionAnimated,
            pendingSearchReveal: pendingSearchReveal,
            theme: theme,
            flow: flow,
            fontSize: fontSize,
            lineHeight: lineHeight,
            margin: margin,
            annotations: annotations,
            onProgress: onProgress,
            onTOCSelection: onTOCSelection,
            onPageInfo: onPageInfo,
            onBoundary: onBoundary,
            onSpeakingChanged: onSpeakingChanged,
            onAnnotation: onAnnotation,
            onNoteRequest: onNoteRequest,
            onAnnotationClick: onAnnotationClick,
            onAnnotationAtSection: onAnnotationAtSection,
            onRemoveAnnotation: onRemoveAnnotation,
            onImageClick: onImageClick,
            onNavigate: onNavigate,
            onAnchorConsumed: onAnchorConsumed,
            onPositionConsumed: onPositionConsumed,
            onSearchConsumed: onSearchConsumed,
            onContentReady: onContentReady
        )
        context.coordinator.scheduleInitialLoadIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.speechBridge.overlayRect = speechOverlayRect
        coordinator.onFind = onFind
        coordinator.update(
            book: book,
            sectionIndex: sectionIndex,
            pendingAnchor: pendingAnchor,
            pendingPosition: pendingPosition,
            pendingPositionAnimated: pendingPositionAnimated,
            pendingSearchReveal: pendingSearchReveal,
            theme: theme,
            flow: flow,
            fontSize: fontSize,
            lineHeight: lineHeight,
            margin: margin,
            annotations: annotations,
            onProgress: onProgress,
            onTOCSelection: onTOCSelection,
            onPageInfo: onPageInfo,
            onBoundary: onBoundary,
            onSpeakingChanged: onSpeakingChanged,
            onAnnotation: onAnnotation,
            onNoteRequest: onNoteRequest,
            onAnnotationClick: onAnnotationClick,
            onAnnotationAtSection: onAnnotationAtSection,
            onRemoveAnnotation: onRemoveAnnotation,
            onImageClick: onImageClick,
            onNavigate: onNavigate,
            onAnchorConsumed: onAnchorConsumed,
            onPositionConsumed: onPositionConsumed,
            onSearchConsumed: onSearchConsumed,
            onContentReady: onContentReady
        )
        if coordinator.hasCompletedInitialLoad {
            coordinator.loadSectionIfNeeded()
        } else {
            coordinator.scheduleInitialLoadIfNeeded()
        }
        if coordinator.lastCommandID != controller.command?.id, let command = controller.command {
            coordinator.lastCommandID = command.id
            Task { @MainActor [weak coordinator] in coordinator?.execute(command.action) }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject {
        private struct Settings: Equatable {
            let theme: ReadingTheme
            let flow: ReaderFlowMode
            let fontSize: Double
            let lineHeight: Double
            let margin: Double
        }

        private let loader = NativeChapterLoader()
        let speechBridge: ReaderSpeechBridge
        private var speech: SpeechSession { speechBridge.session }
        private let logger = Logger(subsystem: "com.obooks.app", category: "reader.native")
        private weak var scrollView: NSScrollView?
        private weak var textView: ReaderTextView?
        private var scrollObserver: NSObjectProtocol?
        private var searchObserver: NSObjectProtocol?
        private var book: BookSummary?
        private var tocIndex = ReaderTOCIndex(spine: [], items: [])
        private var requestedSectionIndex = 0
        private var lastInputSectionIndex: Int?
        private var pendingAnchor: String?
        private var pendingPosition: ReadingPosition?
        private var pendingPositionAnimated = false
        private var pendingSearchReveal: ReaderSearchReveal?
        private var lastConsumedSearchID: UUID?
        private var currentSectionIndex = -1
        private var anchors: [String: Int] = [:]
        private var settings = Settings(theme: .focus, flow: .scrolling(scope: .chapter), fontSize: 18, lineHeight: 1.7, margin: 56)
        private var loadedSettings: Settings?
        private var annotations: [ReaderAnnotation] = []
        private var renderedAnnotationRanges: [(id: UUID, range: NSRange, kind: String)] = []
        private var renderedSearchRange: NSRange?
        private var onProgress: (Double, ReadingPosition) -> Void = { _, _ in }
        private var onTOCSelection: (UUID?) -> Void = { _ in }
        private var onPageInfo: (Int, Int) -> Void = { _, _ in }
        private var onBoundary: (Int) -> Void = { _ in }
        private var onSpeakingChanged: (Bool) -> Void = { _ in }
        private var onAnnotation: (String, String, NSRange) -> Void = { _, _, _ in }
        private var onNoteRequest: (String, NSRange) -> Void = { _, _ in }
        private var onAnnotationClick: (ReaderAnnotation) -> Void = { _ in }
        private var onAnnotationAtSection: (String, String, Int, NSRange) -> Void = { _, _, _, _ in }
        private var onRemoveAnnotation: (UUID) -> Void = { _ in }
        private var onImageClick: (NSImage, NSRect) -> Void = { _, _ in }
        var onFind: () -> Void = {}
        private var onNavigate: (Int, String?) -> Void = { _, _ in }
        private var onAnchorConsumed: () -> Void = {}
        private var onPositionConsumed: () -> Void = {}
        private var onSearchConsumed: () -> Void = {}
        private var onContentReady: () -> Void = {}
        private var pendingProgress: Double?
        private var pendingReadingPosition: ReadingPosition?
        private var positionBeingRestored: ReadingPosition?
        private var progressCallbackScheduled = false
        private var restorationTaskScheduled = false
        private var isRestoringPosition = false
        private var isTornDown = false
        private var loadedBookContent = false
        private var sectionRanges: [String: NSRange] = [:]
        private var sectionIndices: [String: Int] = [:]
        private var sectionAnchors: [String: [String: Int]] = [:]
        private var loadedBookStartIndex = -1
        private var loadedBookEndIndex = -1
    private var loadingAdjacentChapter = false
    private var chapterDocuments: [Int: NativeChapterDocument] = [:]
    private var updatingDocument = false
    private let scrollNavigationRevealOffset: CGFloat = 72
        private var initialLoadTask: Task<Void, Never>?
        private var isInitialLoadScheduled = false
        private var didNotifyContentReady = false
        private(set) var hasCompletedInitialLoad = false
        var lastCommandID: UUID?

        init(speech: SpeechSession? = nil) {
            speechBridge = ReaderSpeechBridge(session: speech ?? SpeechSession())
            super.init()
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            if let searchObserver {
                NotificationCenter.default.removeObserver(searchObserver)
            }
        }

        func attach(scrollView: NSScrollView, textView: ReaderTextView) {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            self.scrollView = scrollView
            self.textView = textView
            isTornDown = false
            if let readerScrollView = scrollView as? ReaderScrollView {
                speechBridge.attach(textView: textView, scrollView: readerScrollView)
                speechBridge.resolveRange = { [weak self] in self?.speechDocumentRange($0) }
                speechBridge.reveal = { [weak self] in self?.revealSpeechPosition($0) }
                speechBridge.restoreAnnotations = { [weak self] in self?.applyAnnotations() }
                speechBridge.highlightColor = { [weak self] in
                    NativeReaderAppearance(theme: self?.settings.theme ?? .focus).speechHighlight
                }
                speechBridge.onSpeakingChanged = { [weak self] in self?.notifySpeakingChanged($0) }
                speech.pageForSentence = { [weak self] index in self?.speechSentencePage(index) }
                readerScrollView.onUserScroll = { [weak self] in
                    self?.handleUserInteraction()
                    self?.speechBridge.follow.userInteraction()
                }
                readerScrollView.pageTurn = { [weak self] direction in
                    guard let self else { return nil }
                    self.handleUserInteraction()
                    return self.preparePageTurn(direction: direction)
                }
                readerScrollView.onPageTurnCompleted = { [weak self] in
                    if self?.speech.state.isActive == true { self?.speechBridge.refresh(followPosition: true) }
                    self?.reportProgress()
                }
                readerScrollView.onKeyboardNavigate = { [weak self] direction in
                    guard let self else { return }
                    self.handleUserInteraction()
                    self.speechBridge.follow.userInteraction()
                    self.turnPage(direction: direction)
                }
                readerScrollView.onViewportSizeChanged = { [weak self] location, viewportOffset in
                    guard let self, self.loadedSettings != nil else { return }
                    self.updatingDocument = true
                    self.updateDocumentLayout()
                    if let location {
                        self.scrollToCharacter(
                            location,
                            animated: false,
                            locationIsGlobal: true,
                            viewportOffset: viewportOffset ?? 0
                        )
                    }
                    self.updatingDocument = false
                    self.alignPagingViewportIfNeeded()
                    self.speechBridge.refresh()
                    self.reportProgress()
                }
            }
            textView.onHighlight = { [weak self] text, range in
                self?.handleHighlight(text: text, range: range)
            }
            textView.onNote = { [weak self] text, range in
                self?.onNoteRequest(text, self?.localizedAnnotationRange(range) ?? range)
            }
            textView.onAnnotationClick = { [weak self] annotation in
                self?.onAnnotationClick(annotation)
            }
            textView.annotationAtLocation = { [weak self] location in
                self?.annotation(at: location)
            }
            textView.onRemoveAnnotation = { [weak self] id in
                self?.onRemoveAnnotation(id)
            }
            textView.onSpeak = { [weak self] location in
                self?.startSpeech(at: location)
            }
            textView.onLink = { [weak self] url in
                self?.openLink(url)
            }
            textView.onImageClick = { [weak self] image, rect in
                self?.onImageClick(image, rect)
            }

            if let searchObserver {
                NotificationCenter.default.removeObserver(searchObserver)
            }
            searchObserver = NotificationCenter.default.addObserver(
                forName: .obooksSearchRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let window = self.scrollView?.window else { return }
                    let target = notification.object as? NSWindow ?? NSApp.keyWindow
                    guard target === window, window.isKeyWindow else { return }
                    self.onFind()
                }
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.alignPagingViewportIfNeeded()
                    self?.reportProgress()
                }
            }
        }

        func update(
            book: BookSummary,
            sectionIndex: Int,
            pendingAnchor: String?,
            pendingPosition: ReadingPosition?,
            pendingPositionAnimated: Bool,
            pendingSearchReveal: ReaderSearchReveal? = nil,
            theme: ReadingTheme,
            flow: ReaderFlowMode = .scrolling(scope: .chapter),
            fontSize: Double,
            lineHeight: Double,
            margin: Double,
            annotations: [ReaderAnnotation],
            onProgress: @escaping (Double, ReadingPosition) -> Void,
            onTOCSelection: @escaping (UUID?) -> Void = { _ in },
            onPageInfo: @escaping (Int, Int) -> Void = { _, _ in },
            onBoundary: @escaping (Int) -> Void,
            onSpeakingChanged: @escaping (Bool) -> Void,
            onAnnotation: @escaping (String, String, NSRange) -> Void,
            onNoteRequest: @escaping (String, NSRange) -> Void,
            onAnnotationClick: @escaping (ReaderAnnotation) -> Void = { _ in },
            onAnnotationAtSection: @escaping (String, String, Int, NSRange) -> Void = { _, _, _, _ in },
            onRemoveAnnotation: @escaping (UUID) -> Void = { _ in },
            onImageClick: @escaping (NSImage, NSRect) -> Void = { _, _ in },
            onNavigate: @escaping (Int, String?) -> Void,
            onAnchorConsumed: @escaping () -> Void,
            onPositionConsumed: @escaping () -> Void,
            onSearchConsumed: @escaping () -> Void = {},
            onContentReady: @escaping () -> Void = {}
        ) {
            let nextSettings = Settings(theme: theme, flow: flow, fontSize: fontSize, lineHeight: lineHeight, margin: margin)
            let settingsChanged = settings != nextSettings
            let sectionChanged = lastInputSectionIndex != sectionIndex
            if sectionChanged, lastInputSectionIndex != nil, currentSectionIndex != sectionIndex {
                speechBridge.follow.userInteraction()
            }
            if settingsChanged || sectionChanged
                || self.pendingAnchor != pendingAnchor
                || self.pendingPosition != pendingPosition
                || self.pendingSearchReveal != pendingSearchReveal {
                (scrollView as? ReaderScrollView)?.prepareForProgrammaticScroll()
            }
            let preservedPosition = settingsChanged ? currentReadingPosition() : nil
            if settingsChanged { chapterDocuments.removeAll() }
            if self.book?.id != book.id {
                tocIndex = ReaderTOCIndex(spine: book.spine, items: book.toc)
                speech.configure(
                    spineIDs: book.spine.map { $0.id.isEmpty ? $0.href : $0.id },
                    title: { index in
                        guard book.spine.indices.contains(index) else { return "" }
                        func findTitle(_ items: [EPUBTOCItem]) -> String? {
                            for item in items {
                                if item.href.split(separator: "#").first.map(String.init) == book.spine[index].href { return item.label }
                                if let title = findTitle(item.children) { return title }
                            }
                            return nil
                        }
                        return findTitle(book.toc) ?? "第 \(index + 1) 章"
                    },
                    loadText: { [weak self] index in
                        guard let self else { throw CocoaError(.fileReadUnknown) }
                        return try self.chapterDocument(at: index).attributedText.string
                    }
                )
            }
            self.book = book
            if sectionChanged { requestedSectionIndex = sectionIndex }
            lastInputSectionIndex = sectionIndex
            let anchorChanged = self.pendingAnchor != pendingAnchor
            self.pendingAnchor = pendingAnchor
            let positionChanged = self.pendingPosition != pendingPosition
            self.pendingPosition = pendingPosition
            let positionAnimated = pendingPositionAnimated
            self.pendingPositionAnimated = pendingPositionAnimated
            self.pendingSearchReveal = pendingSearchReveal
            settings = nextSettings
            if let scrollView {
                scrollView.hasVerticalScroller = flow.scrollScope != nil
                scrollView.hasHorizontalScroller = false
                (scrollView as? ReaderScrollView)?.configure(flow: flow)
            }
            let annotationsChanged = self.annotations != annotations
            self.annotations = annotations
            self.onProgress = onProgress
            self.onTOCSelection = onTOCSelection
            self.onPageInfo = onPageInfo
            self.onBoundary = onBoundary
            self.onSpeakingChanged = onSpeakingChanged
            self.onAnnotation = onAnnotation
            self.onNoteRequest = onNoteRequest
            self.onAnnotationClick = onAnnotationClick
            self.onAnnotationAtSection = onAnnotationAtSection
            self.onRemoveAnnotation = onRemoveAnnotation
            self.onImageClick = onImageClick
            self.onNavigate = onNavigate
            self.onAnchorConsumed = onAnchorConsumed
            self.onPositionConsumed = onPositionConsumed
            self.onSearchConsumed = onSearchConsumed
            self.onContentReady = onContentReady
            if annotationsChanged {
                applyAnnotations()
                speechBridge.refresh()
            }
            if anchorChanged {
                handleUserInteraction()
                speechBridge.follow.userInteraction()
            }
            if consumeSearchRevealIfReady() {
                if self.pendingPosition != nil {
                    consumePendingPosition()
                }
                return
            }
            if anchorChanged,
               let pendingAnchor,
               let location = anchorLocation(pendingAnchor),
               (currentSectionIndex == sectionIndex || loadedBookContent) {
                scrollToCharacter(
                    location,
                    animated: true,
                    locationIsGlobal: loadedBookContent,
                    viewportOffset: settings.flow.isPaging ? 0 : scrollNavigationRevealOffset
                )
                consumePendingAnchor()
            }
            if positionChanged,
               let pendingPosition,
               isPositionLoaded(pendingPosition),
               (currentSectionIndex == sectionIndex || loadedBookContent) {
                if positionAnimated {
                    handleUserInteraction()
                    speechBridge.follow.userInteraction()
                    scrollToReadingPosition(
                        pendingPosition,
                        animated: true,
                        revealBelowChrome: !settings.flow.isPaging
                    )
                    consumePendingPosition()
                    return
                }
                positionBeingRestored = pendingPosition
                isRestoringPosition = true
                scrollToReadingPosition(pendingPosition, animated: false)
                schedulePositionRestoration()
                consumePendingPosition()
            }
            if let preservedPosition, pendingPosition == nil, pendingAnchor == nil, pendingSearchReveal == nil {
                positionBeingRestored = preservedPosition
                isRestoringPosition = true
            }
        }

        func loadSectionIfNeeded() {
            guard (scrollView as? ReaderScrollView)?.isPageTransitionActive != true else { return }
            if loadedBookContent,
               settings.flow.scrollScope == .book,
               loadedSettings == settings {
                guard let book,
                      book.spine.indices.contains(requestedSectionIndex) else { return }
                let identity = spineIdentity(book.spine[requestedSectionIndex])
                guard sectionRanges[identity] != nil else {
                    loadBookSectionFromScratch()
                    return
                }
                let sectionChanged = currentSectionIndex != requestedSectionIndex
                if sectionChanged {
                    handleUserInteraction()
                    if let pendingAnchor,
                       let location = anchorLocation(pendingAnchor) {
                        scrollToCharacter(
                            location,
                            animated: true,
                            locationIsGlobal: true,
                            viewportOffset: settings.flow.isPaging ? 0 : scrollNavigationRevealOffset
                        )
                        consumePendingAnchor()
                    } else {
                        if pendingAnchor != nil {
                            consumePendingAnchor()
                        }
                        if let range = sectionRanges[identity] {
                            scrollToCharacter(range.location, animated: true, locationIsGlobal: true)
                        }
                    }
                }
                currentSectionIndex = requestedSectionIndex
                if consumeSearchRevealIfReady(), pendingPosition != nil {
                    consumePendingPosition()
                }
                reportProgress()
                return
            }
            guard currentSectionIndex != requestedSectionIndex || loadedSettings != settings else { return }
            guard let book, let textView, let scrollView else { return }
            updatingDocument = true
            defer { updatingDocument = false; reportProgress() }
            let previousSectionIndex = currentSectionIndex
            if let pendingPosition,
               book.spine.indices.contains(requestedSectionIndex),
               spineIdentity(book.spine[requestedSectionIndex]) == pendingPosition.spineID {
                positionBeingRestored = pendingPosition
                isRestoringPosition = true
            }
            clearSpeechRange()
            let appearance = NativeReaderAppearance(theme: settings.theme)
            do {
                let loaded = try loadContent(book: book)
                let attributedText = loaded.document.attributedText
                textView.backgroundColor = appearance.background
                textView.insertionPointColor = appearance.accent
                textView.selectedTextAttributes = settings.flow.isPaging
                    ? [.foregroundColor: appearance.foreground]
                    : [
                        .backgroundColor: appearance.selection,
                        .foregroundColor: appearance.foreground
                    ]
                textView.setReadingInsets(
                    horizontal: max(34, settings.margin),
                    vertical: max(64, settings.margin)
                )
                renderedAnnotationRanges.removeAll()
                clearSearchHighlight()
                textView.textStorage?.setAttributedString(attributedText)
                textView.configurePageColumns(
                    settings.flow.isPaging ? settings.flow.pageColumns.rawValue : 0,
                    viewportHeight: currentViewportHeight()
                )
                scrollView.backgroundColor = appearance.background
                currentSectionIndex = requestedSectionIndex
                anchors = loaded.document.anchors
                sectionRanges = loaded.ranges
                sectionIndices = loaded.indices
                sectionAnchors = loaded.sectionAnchors
                loadedBookContent = loaded.isBook
                if loaded.isBook {
                    loadedBookStartIndex = requestedSectionIndex
                    loadedBookEndIndex = requestedSectionIndex
                } else {
                    loadedBookStartIndex = -1
                    loadedBookEndIndex = -1
                }
                loadedSettings = settings
                applyAnnotations()
                updateDocumentLayout()
                if consumeSearchRevealIfReady() {
                    if pendingPosition != nil {
                        consumePendingPosition()
                    }
                } else if let pendingAnchor, let location = anchorLocation(pendingAnchor) {
                    scrollToCharacter(
                        location,
                        animated: false,
                        locationIsGlobal: loadedBookContent,
                        viewportOffset: settings.flow.isPaging ? 0 : scrollNavigationRevealOffset
                    )
                    consumePendingAnchor()
                } else if pendingAnchor != nil {
                    consumePendingAnchor()
                } else if let positionBeingRestored,
                          isPositionLoaded(positionBeingRestored) {
                    if pendingPositionAnimated {
                        handleUserInteraction()
                        scrollToReadingPosition(
                            positionBeingRestored,
                            animated: true,
                            revealBelowChrome: !settings.flow.isPaging
                        )
                    } else {
                        scrollToReadingPosition(positionBeingRestored, animated: false)
                        schedulePositionRestoration()
                    }
                    if pendingPosition != nil {
                        consumePendingPosition()
                    }
                } else if let pendingPosition {
                    if isPositionForCurrentSection(pendingPosition) {
                        scrollToReadingPosition(pendingPosition, animated: false)
                    }
                    consumePendingPosition()
                } else if !settings.flow.isPaging,
                          previousSectionIndex >= 0, requestedSectionIndex < previousSectionIndex {
                    scrollToEnd()
                } else {
                    scrollView.contentView.scroll(to: .zero)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
                alignPagingViewportIfNeeded()
                reportProgress()
                speechBridge.refresh()
            } catch {
                logger.error("加载原生章节失败: section=\(self.requestedSectionIndex), error=\(error.localizedDescription, privacy: .public)")
                textView.string = "无法显示这一章\n\n\(error.localizedDescription)"
                currentSectionIndex = requestedSectionIndex
                loadedSettings = settings
            }
        }

        func scheduleInitialLoadIfNeeded() {
            guard !isInitialLoadScheduled else { return }
            isInitialLoadScheduled = true
            guard let book, book.spine.indices.contains(requestedSectionIndex) else {
                hasCompletedInitialLoad = true
                loadSectionIfNeeded()
                notifyContentReady()
                return
            }
            let sectionIndex = requestedSectionIndex
            let fontSize = settings.fontSize
            let lineHeight = settings.lineHeight
            let theme = settings.theme
            let settingsSnapshot = settings
            let started = Date()
            logger.info("开始异步加载章节: section=\(sectionIndex)")
            initialLoadTask = Task { [weak self] in
                let document = await Task.detached(priority: .userInitiated) {
                    try? NativeChapterLoader().loadDocument(
                        book: book,
                        sectionIndex: sectionIndex,
                        fontSize: fontSize,
                        lineHeight: lineHeight,
                        foreground: NativeReaderAppearance(theme: theme).foreground
                    )
                }.value
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, !self.isTornDown else { return }
                    let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                    if let document,
                       self.settings == settingsSnapshot,
                       self.requestedSectionIndex == sectionIndex
                    {
                        self.chapterDocuments[sectionIndex] = document
                        self.logger.info(
                            "异步章节加载完成: section=\(sectionIndex), characters=\(document.attributedText.length), durationMs=\(elapsedMs)"
                        )
                    } else {
                        self.logger.info("异步章节未直接应用, 将按当前设置加载: section=\(sectionIndex), durationMs=\(elapsedMs)")
                    }
                    self.hasCompletedInitialLoad = true
                    self.loadSectionIfNeeded()
                    self.notifyContentReady()
                }
            }
        }

        private func notifyContentReady() {
            guard !didNotifyContentReady else { return }
            didNotifyContentReady = true
            if let textView {
                textView.window?.makeFirstResponder(textView)
            }
            alignPagingViewportIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.alignPagingViewportIfNeeded()
            }
            onContentReady()
        }

        func execute(_ action: ReaderAction) {
            guard !isTornDown else { return }
            handleUserInteraction()
            switch action {
            case .nextPage:
                speechBridge.follow.userInteraction()
                turnPage(direction: 1)
            case .previousPage:
                speechBridge.follow.userInteraction()
                turnPage(direction: -1)
            case .seek(let fraction, let animated):
                speechBridge.follow.userInteraction()
                (scrollView as? ReaderScrollView)?.prepareForProgrammaticScroll()
                seek(to: fraction, animated: animated)
            case .toggleSpeech:
                if speech.state == .idle {
                    startSpeech(at: firstVisibleCharacterLocation())
                } else { speech.toggle() }
            case .stopSpeech:
                stopSpeech()
            case .speechSentence(let index): speech.playSentence(index)
            case .speechStep(let direction, let paragraph): speech.step(direction, byParagraph: paragraph)
            case .speechRate(let rate): speech.setRate(rate)
            case .speechVoice(let voice): speech.setVoice(voice)
            case .revealSpeech: speechBridge.follow.resumeNow()
            case .jumpToPage(let page):
                speechBridge.follow.userInteraction()
                (scrollView as? ReaderScrollView)?.prepareForProgrammaticScroll()
                jumpToPage(page)
            }
        }

        func teardown() {
            isTornDown = true
            (scrollView as? ReaderScrollView)?.prepareForProgrammaticScroll()
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = nil
            if let searchObserver {
                NotificationCenter.default.removeObserver(searchObserver)
            }
            searchObserver = nil
            (scrollView as? ReaderScrollView)?.onUserScroll = nil
            (scrollView as? ReaderScrollView)?.pageTurn = nil
            (scrollView as? ReaderScrollView)?.onPageTurnCompleted = nil
            (scrollView as? ReaderScrollView)?.onViewportSizeChanged = nil
            (scrollView as? ReaderScrollView)?.onKeyboardNavigate = nil
            onProgress = { _, _ in }
            onTOCSelection = { _ in }
            onPageInfo = { _, _ in }
            onBoundary = { _ in }
            onSpeakingChanged = { _ in }
            onAnnotation = { _, _, _ in }
            onNoteRequest = { _, _ in }
            onAnnotationClick = { _ in }
            onAnnotationAtSection = { _, _, _, _ in }
            onRemoveAnnotation = { _ in }
            onImageClick = { _, _ in }
            onFind = {}
            onNavigate = { _, _ in }
            onAnchorConsumed = {}
            onPositionConsumed = {}
            onSearchConsumed = {}
            clearSearchHighlight()
            pendingSearchReveal = nil
            lastConsumedSearchID = nil
            pendingProgress = nil
            pendingReadingPosition = nil
            speechBridge.teardown()
            renderedAnnotationRanges.removeAll()
            sectionRanges.removeAll()
            sectionIndices.removeAll()
            sectionAnchors.removeAll()
            loadedBookContent = false
            loadedBookStartIndex = -1
            loadedBookEndIndex = -1
            loadingAdjacentChapter = false
            initialLoadTask?.cancel()
            initialLoadTask = nil
            chapterDocuments.removeAll()
            textView?.onHighlight = nil
            textView?.onNote = nil
            textView?.onAnnotationClick = nil
            textView?.annotationAtLocation = nil
            textView?.onRemoveAnnotation = nil
            textView?.onSpeak = nil
            textView?.onLink = nil
            textView?.onImageClick = nil
        }

        private func schedulePositionRestoration() {
            guard !restorationTaskScheduled else { return }
            restorationTaskScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restorationTaskScheduled = false
                guard self.isRestoringPosition,
                      let position = self.positionBeingRestored,
                      self.isPositionLoaded(position) else { return }
                self.scrollToReadingPosition(position, animated: false)
                self.isRestoringPosition = false
                self.positionBeingRestored = nil
                self.alignPagingViewportIfNeeded()
                self.reportProgress()
            }
        }

        private func handleUserInteraction() {
            isRestoringPosition = false
            positionBeingRestored = nil
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

        private func consumePendingSearch() {
            pendingSearchReveal = nil
            let callback = onSearchConsumed
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown else { return }
                callback()
            }
        }

        @discardableResult
        private func consumeSearchRevealIfReady() -> Bool {
            guard let reveal = pendingSearchReveal, isSearchRevealReady(reveal) else { return false }
            if lastConsumedSearchID == reveal.id {
                consumePendingSearch()
                return false
            }
            handleUserInteraction()
            speechBridge.follow.userInteraction()
            revealSearch(reveal)
            lastConsumedSearchID = reveal.id
            consumePendingSearch()
            return true
        }

        private func isSearchRevealReady(_ reveal: ReaderSearchReveal) -> Bool {
            guard loadedSettings != nil, let textView, !textView.string.isEmpty else { return false }
            if loadedBookContent {
                return sectionRanges[reveal.spineID] != nil
            }
            guard let book, book.spine.indices.contains(currentSectionIndex) else { return false }
            return spineIdentity(book.spine[currentSectionIndex]) == reveal.spineID
        }

        private func revealSearch(_ reveal: ReaderSearchReveal) {
            guard let textView else { return }
            let text = textView.string as NSString
            let scope: NSRange
            if loadedBookContent, let range = sectionRanges[reveal.spineID] {
                scope = range
            } else {
                scope = NSRange(location: 0, length: text.length)
            }
            guard scope.length > 0 else { return }
            let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            var searchRange = scope
            var found = NSRange(location: NSNotFound, length: 0)
            var first = NSRange(location: NSNotFound, length: 0)
            for index in 0...reveal.occurrenceIndex {
                let match = text.range(of: reveal.query, options: options, range: searchRange)
                guard match.location != NSNotFound else { break }
                if index == 0 { first = match }
                found = match
                let next = NSMaxRange(match)
                let end = NSMaxRange(scope)
                guard next < end else { break }
                searchRange = NSRange(location: next, length: end - next)
            }
            if found.location == NSNotFound {
                found = first.location == NSNotFound
                    ? text.range(of: reveal.query, options: options, range: scope)
                    : first
            }
            guard found.location != NSNotFound else { return }
            logger.debug(
                "定位搜索结果: occurrence=\(reveal.occurrenceIndex), offset=\(found.location)"
            )
            applySearchHighlight(found)
            textView.setSelectedRange(found)
            scrollToCharacter(
                found.location,
                animated: true,
                locationIsGlobal: true,
                viewportOffset: settings.flow.isPaging ? 0 : scrollNavigationRevealOffset
            )
        }

        private func applySearchHighlight(_ range: NSRange) {
            clearSearchHighlight()
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let full = NSRange(location: 0, length: textView.string.utf16.count)
            let clipped = NSIntersectionRange(range, full)
            guard clipped.length > 0 else { return }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NativeReaderAppearance(theme: settings.theme).searchHighlight,
                forCharacterRange: clipped
            )
            renderedSearchRange = clipped
        }

        private func reapplySearchHighlight() {
            guard let range = renderedSearchRange else { return }
            let preserved = range
            renderedSearchRange = nil
            applySearchHighlight(preserved)
        }

        private func clearSearchHighlight() {
            if let range = renderedSearchRange,
               let textView,
               let layoutManager = textView.layoutManager
            {
                let full = NSRange(location: 0, length: textView.string.utf16.count)
                let clipped = NSIntersectionRange(range, full)
                if clipped.length > 0 {
                    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clipped)
                }
            }
            renderedSearchRange = nil
        }

        private func jumpToPage(_ page: Int) {
            guard settings.flow.isPaging, let textView else { return }
            let count = max(1, textView.pageCount)
            let target = min(max(page, 1), count) - 1
            scroll(to: CGFloat(target) * currentViewportHeight(), animated: true)
            reportProgress()
        }

        private func isPositionForCurrentSection(_ position: ReadingPosition) -> Bool {
            guard let book, book.spine.indices.contains(currentSectionIndex) else { return false }
            return spineIdentity(book.spine[currentSectionIndex]) == position.spineID
        }

        private func isPositionLoaded(_ position: ReadingPosition) -> Bool {
            if loadedBookContent {
                return sectionRanges[position.spineID] != nil
            }
            return isPositionForCurrentSection(position)
        }

        private func anchorLocation(_ anchor: String) -> Int? {
            guard loadedBookContent,
                  let book,
                  book.spine.indices.contains(requestedSectionIndex) else {
                return anchors[anchor]
            }
            let identity = spineIdentity(book.spine[requestedSectionIndex])
            guard let localLocation = sectionAnchors[identity]?[anchor] else { return nil }
            return (sectionRanges[identity]?.location ?? 0) + localLocation
        }

        private func localizedAnnotationRange(_ range: NSRange) -> NSRange {
            guard loadedBookContent,
                  let section = sectionRanges.first(where: {
                      NSIntersectionRange(range, $0.value).length > 0
                  }),
                  let sectionIndex = sectionIndices[section.key] else {
                return range
            }
            currentSectionIndex = sectionIndex
            return NSRange(
                location: max(0, range.location - section.value.location),
                length: range.length
            )
        }

        private func currentReadingPosition() -> ReadingPosition? {
            guard let book,
                  !book.spine.isEmpty,
                  book.spine.indices.contains(currentSectionIndex) else { return nil }
            let visibleLocation = firstVisibleCharacterLocation()
            var index = currentSectionIndex
            var localLocation = visibleLocation
            if loadedBookContent,
               let visibleSection = sectionRanges.first(where: { NSLocationInRange(visibleLocation, $0.value) }),
               let visibleIndex = sectionIndices[visibleSection.key] {
                index = visibleIndex
                localLocation = visibleLocation - visibleSection.value.location
            }
            return ReadingPosition(
                spineID: spineIdentity(book.spine[index]),
                characterOffset: max(0, localLocation),
                viewportOffset: textView?.viewportOffset(forCharacter: visibleLocation).map(Double.init)
            )
        }

        private func spineIdentity(_ item: EPUBSpineItem) -> String {
            item.id.isEmpty ? item.href : item.id
        }

        private func loadBookSectionFromScratch() {
            loadedBookContent = false
            loadedSettings = nil
            sectionRanges.removeAll()
            sectionIndices.removeAll()
            sectionAnchors.removeAll()
            anchors.removeAll()
            loadSectionIfNeeded()
        }

        private func loadContent(
            book: BookSummary
        ) throws -> (document: NativeChapterDocument, ranges: [String: NSRange], indices: [String: Int], sectionAnchors: [String: [String: Int]], isBook: Bool) {
            guard settings.flow.scrollScope == .book else {
                let document = try chapterDocument(at: requestedSectionIndex)
                let identity = book.spine.indices.contains(requestedSectionIndex)
                    ? spineIdentity(book.spine[requestedSectionIndex])
                    : ""
                return (document, identity.isEmpty ? [:] : [identity: NSRange(location: 0, length: document.attributedText.length)], identity.isEmpty ? [:] : [identity: requestedSectionIndex], identity.isEmpty ? [:] : [identity: document.anchors], false)
            }

            let index = min(max(requestedSectionIndex, 0), max(book.spine.count - 1, 0))
            let chapter = try chapterDocument(at: index)
            let identity = spineIdentity(book.spine[index])
            let ranges = [identity: NSRange(location: 0, length: chapter.attributedText.length)]
            let indices = [identity: index]
            let sectionAnchors = [identity: chapter.anchors]
            logger.info("加载全书滚动起始章节: chapter=\(index + 1)/\(book.spine.count, privacy: .public), characters=\(chapter.attributedText.length, privacy: .public)")
            return (
                chapter,
                ranges,
                indices,
                sectionAnchors,
                true
            )
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

        private func scrollToCharacter(
            _ location: Int,
            animated: Bool,
            locationIsGlobal: Bool = false,
            viewportOffset: CGFloat = 0
        ) {
            guard let textView, let scrollView else { return }
            let length = (textView.string as NSString).length
            guard length > 0 else { return }
            let globalLocation: Int
            if loadedBookContent,
               !locationIsGlobal,
               let book,
               book.spine.indices.contains(requestedSectionIndex) {
                let identity = spineIdentity(book.spine[requestedSectionIndex])
                globalLocation = (sectionRanges[identity]?.location ?? 0) + location
            } else {
                globalLocation = location
            }
            let clampedLocation = min(max(globalLocation, 0), length - 1)
            if let pageOffset = textView.pageOffset(forCharacter: clampedLocation) {
                scroll(to: pageOffset, animated: animated)
                return
            }
            if let documentY = textView.documentY(forCharacter: clampedLocation) {
                scroll(to: documentY - viewportOffset, animated: animated)
                return
            }
            let range = NSRange(location: clampedLocation, length: 1)
            let scroll = {
                textView.scrollRangeToVisible(range)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    scroll()
                }
            } else {
                scroll()
            }
        }

        private func scrollToReadingPosition(_ position: ReadingPosition, animated: Bool) {
            scrollToReadingPosition(position, animated: animated, revealBelowChrome: false)
        }

        private func scrollToReadingPosition(
            _ position: ReadingPosition,
            animated: Bool,
            revealBelowChrome: Bool
        ) {
            let globalLocation: Int
            if loadedBookContent, let range = sectionRanges[position.spineID] {
                globalLocation = range.location + position.characterOffset
            } else {
                globalLocation = position.characterOffset
            }
            scrollToCharacter(
                globalLocation,
                animated: animated,
                locationIsGlobal: true,
                viewportOffset: revealBelowChrome
                    ? scrollNavigationRevealOffset
                    : CGFloat(position.viewportOffset ?? 0)
            )
        }

        private func startSpeech(at location: Int) {
            guard let book, book.spine.indices.contains(currentSectionIndex) else { return }
            if loadedBookContent {
                for (identity, range) in sectionRanges where NSLocationInRange(location, range) {
                    if let index = sectionIndices[identity] {
                        speech.start(section: index, offset: location - range.location)
                        return
                    }
                }
            }
            speech.start(section: currentSectionIndex, offset: location)
        }

        private func stopSpeech() {
            speech.stop()
            clearSpeechRange()
        }

        func showSpeechRange(_ range: NSRange) {
            revealLoadedSpeechRange(range)
            speechBridge.highlight(range)
        }

        private func clearSpeechRange() {
            speechBridge.clearHighlight()
        }

        private func speechDocumentRange(_ position: SpeechPosition) -> NSRange? {
            if loadedBookContent {
                guard let section = sectionRanges[position.spineID] else { return nil }
                return NSRange(location: section.location + position.range.location, length: position.range.length)
            }
            guard currentSectionIndex == position.sectionIndex else { return nil }
            return position.range
        }

        private func speechSentencePage(_ index: Int) -> Int? {
            guard settings.flow.isPaging, speech.sentences.indices.contains(index),
                  let book, book.spine.indices.contains(speech.sectionIndex), let textView, let scrollView else { return nil }
            let position = SpeechPosition(sectionIndex: speech.sectionIndex,
                spineID: spineIdentity(book.spine[speech.sectionIndex]), range: speech.sentences[index].range)
            let viewportHeight = currentViewportHeight()
            if let range = speechDocumentRange(position), let offset = textView.pageOffset(forCharacter: range.location) {
                return Int((offset / viewportHeight).rounded()) + 1
            }
            guard let document = try? chapterDocument(at: position.sectionIndex) else { return nil }
            let measurement = ReaderTextView(frame: NSRect(origin: .zero, size: NSSize(width: scrollView.contentSize.width, height: viewportHeight)))
            measurement.isVerticallyResizable = true
            measurement.isHorizontallyResizable = false
            measurement.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            measurement.preferredReadingWidth = textView.preferredReadingWidth
            measurement.setReadingInsets(horizontal: max(34, settings.margin), vertical: max(64, settings.margin))
            measurement.textStorage?.setAttributedString(document.attributedText)
            measurement.configurePageColumns(settings.flow.pageColumns.rawValue, viewportHeight: viewportHeight)
            guard let offset = measurement.pageOffset(forCharacter: position.range.location) else { return nil }
            return Int((offset / viewportHeight).rounded()) + 1
        }

        private func revealSpeechPosition(_ position: SpeechPosition) {
            guard !isTornDown, !updatingDocument,
                  let scrollView = scrollView as? ReaderScrollView,
                  !scrollView.isPageTransitionActive else { return }
            if let range = speechDocumentRange(position) {
                revealLoadedSpeechRange(range)
                return
            }
            guard let book, book.spine.indices.contains(position.sectionIndex) else { return }
            let oldIndex = currentSectionIndex
            do {
                let document = try chapterDocument(at: position.sectionIndex)
                scrollView.transitionContent(direction: position.sectionIndex >= oldIndex ? 1 : -1) { [self] in
                    updatingDocument = true
                    defer { updatingDocument = false }
                    installPageChapter(document, at: position.sectionIndex)
                    if settings.flow.scrollScope == .book {
                        loadedBookContent = true
                        loadedBookStartIndex = position.sectionIndex
                        loadedBookEndIndex = position.sectionIndex
                        sectionRanges = [position.spineID: NSRange(location: 0, length: document.attributedText.length)]
                        sectionIndices = [position.spineID: position.sectionIndex]
                        sectionAnchors = [position.spineID: document.anchors]
                    }
                    scrollToCharacter(position.range.location, animated: false, locationIsGlobal: true,
                        viewportOffset: settings.flow.isPaging ? 0 : 100)
                    speechBridge.refresh()
                    // 自动导航始终提交, 用户手势的取消仍使用原有的回滚入口.
                    return ReaderPageTurn(rollback: {})
                }
            } catch {
                logger.error("朗读定位失败: chapter=\(position.sectionIndex + 1), error=\(error.localizedDescription)")
            }
        }

        private func revealLoadedSpeechRange(_ range: NSRange) {
            guard let textView, let scrollView = scrollView as? ReaderScrollView,
                  range.location < textView.string.utf16.count,
                  !scrollView.isPageTransitionActive else { return }
            if let target = textView.pageOffset(forCharacter: range.location) {
                let current = scrollView.contentView.bounds.minY
                guard abs(target - current) > 1 else { return }
                // 同一页的少量 Y 偏差只静默对齐, 避免刚进书或 TTS 首包时播放假翻页动画.
                let step = max(1, textView.pageViewportHeight)
                let currentPage = Int((current / step).rounded())
                let targetPage = Int((target / step).rounded())
                if currentPage == targetPage {
                    scrollView.scroll(to: target, animated: false)
                    return
                }
                scrollView.transitionContent(direction: target > current ? 1 : -1) { [weak scrollView] in
                    scrollView?.scroll(to: target, animated: false)
                    return ReaderPageTurn(rollback: {})
                }
                return
            }
            guard let y = textView.documentY(forCharacter: range.location) else { return }
            let viewport = scrollView.contentView.bounds
            var top: CGFloat = 76
            var bottom = viewport.height - 64
            let overlay = speechBridge.overlayRect
            if !overlay.isEmpty {
                let above = overlay.minY - 12 - top
                let below = bottom - overlay.maxY - 12
                if above >= below { bottom = min(bottom, overlay.minY - 12) }
                else { top = max(top, overlay.maxY + 12) }
            }
            let lineHeight = CGFloat(settings.fontSize * settings.lineHeight)
            let localY = y - viewport.minY
            guard localY < top || localY + lineHeight > bottom else { return }
            let anchor = top + max(0, bottom - top - lineHeight) / 3
            scrollView.scroll(to: y - anchor, animated: true, forSpeech: true)
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
            for annotation in annotations where loadedBookContent || annotation.sectionIndex == currentSectionIndex {
                var globalRange: NSRange
                if loadedBookContent,
                   let book,
                   book.spine.indices.contains(annotation.sectionIndex) {
                    let identity = spineIdentity(book.spine[annotation.sectionIndex])
                    guard let sectionRange = sectionRanges[identity] else { continue }
                    let localRange = NSIntersectionRange(
                        annotation.range,
                        NSRange(location: 0, length: sectionRange.length)
                    )
                    guard localRange.length > 0 else { continue }
                    globalRange = NSRange(
                        location: sectionRange.location + localRange.location,
                        length: localRange.length
                    )
                } else {
                    let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
                    globalRange = NSIntersectionRange(annotation.range, fullRange)
                }
                if annotation.kind == "highlight" {
                    let expected = textView.string as NSString
                    let repaired = expected.range(of: annotation.text)
                    if expected.substring(with: globalRange) != annotation.text,
                       repaired.location != NSNotFound {
                        globalRange = repaired
                    }
                }
                let range = NSIntersectionRange(globalRange, fullRange)
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
                renderedAnnotationRanges.append((annotation.id, range, annotation.kind))
            }
            reapplySearchHighlight()
        }

        private func annotation(at location: Int) -> ReaderAnnotation? {
            guard let rendered = renderedAnnotationRanges.first(where: {
                NSLocationInRange(location, $0.range)
            }) else { return nil }
            return annotations.first { $0.id == rendered.id }
        }

        private func handleHighlight(text: String, range: NSRange) {
            guard loadedBookContent,
                  let textView,
                  range.length > 0 else {
                onAnnotation(text, "highlight", localizedAnnotationRange(range))
                return
            }
            let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
            let selection = NSIntersectionRange(range, fullRange)
            guard selection.length > 0 else { return }
            let sections = sectionRanges.compactMap { identity, sectionRange -> (Int, NSRange)? in
                guard let index = sectionIndices[identity] else { return nil }
                return (index, sectionRange)
            }.sorted { $0.1.location < $1.1.location }
            var emitted = false
            for (index, sectionRange) in sections {
                let intersection = NSIntersectionRange(selection, sectionRange)
                guard intersection.length > 0 else { continue }
                let localRange = NSRange(
                    location: intersection.location - sectionRange.location,
                    length: intersection.length
                )
                let localText = (textView.string as NSString).substring(with: intersection)
                onAnnotationAtSection(localText, "highlight", index, localRange)
                emitted = true
            }
            if !emitted {
                onAnnotation(text, "highlight", localizedAnnotationRange(selection))
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
                      !self.updatingDocument,
                      (self.scrollView as? ReaderScrollView)?.isPageTransitionActive != true,
                      let value = self.pendingProgress,
                      let position = self.pendingReadingPosition else {
                    self.pendingProgress = nil
                    self.pendingReadingPosition = nil
                    return
                }
                self.pendingProgress = nil
                self.pendingReadingPosition = nil
                self.onProgress(value, position)
                let anchors = self.loadedBookContent
                    ? self.sectionAnchors[position.spineID] ?? [:]
                    : self.anchors
                self.onTOCSelection(self.tocIndex.entryID(at: position, anchors: anchors))
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
            guard let textView else { return 0 }
            let viewportHeight = currentViewportHeight()
            textView.updateDocumentHeight(minimumHeight: viewportHeight)
            return max(viewportHeight, textView.frame.height)
        }

        private func currentViewportHeight() -> CGFloat {
            guard let scrollView else { return 1 }
            let height = scrollView.contentView.bounds.height
            if height > 1 { return height }
            let contentHeight = scrollView.contentSize.height
            if contentHeight > 1 { return contentHeight }
            return max(1, scrollView.bounds.height)
        }

        private func alignPagingViewportIfNeeded() {
            guard settings.flow.isPaging,
                  !updatingDocument,
                  (scrollView as? ReaderScrollView)?.isPageTransitionActive != true,
                  let scrollView else { return }
            let step = currentViewportHeight()
            let current = scrollView.contentView.bounds.origin.y
            let target = (current / step).rounded() * step
            guard abs(target - current) > 0.5 else { return }
            logger.debug("对齐分页视口: from=\(current, privacy: .public), to=\(target, privacy: .public)")
            scroll(to: target, animated: false)
        }

        private func maximumScrollOffset() -> CGFloat {
            guard let scrollView, let textView else { return 0 }
            return max(0, textView.frame.height - scrollView.contentView.bounds.height)
        }

        private func turnPage(direction: Int) {
            if settings.flow.isPaging, let scrollView = scrollView as? ReaderScrollView {
                scrollView.turnPage(direction: direction)
                return
            }
            guard let scrollView else { return }
            let current = scrollView.contentView.bounds.origin.y
            let maximum = maximumScrollOffset()
            if (direction > 0 && current >= maximum - 2) || (direction < 0 && current <= 2) {
                if settings.flow.scrollScope == .chapter { notifyBoundary(direction) }
                return
            }
            let amount = max(240, scrollView.contentView.bounds.height * 0.94)
            scroll(to: min(maximum, max(0, current + CGFloat(direction) * amount)), animated: true)
        }

        private func chapterDocument(at index: Int) throws -> NativeChapterDocument {
            if let document = chapterDocuments[index] { return document }
            guard let book else { throw EPUBImportError.invalidPackage("书籍未加载") }
            let document = try loader.loadDocument(
                book: book, sectionIndex: index, fontSize: settings.fontSize,
                lineHeight: settings.lineHeight,
                foreground: NativeReaderAppearance(theme: settings.theme).foreground
            )
            chapterDocuments[index] = document
            chapterDocuments = chapterDocuments.filter { abs($0.key - index) <= 1 }
            return document
        }

        private func installPageChapter(_ document: NativeChapterDocument, at index: Int) {
            guard let textView else { return }
            clearSpeechRange()
            renderedAnnotationRanges.removeAll()
            clearSearchHighlight()
            textView.textStorage?.setAttributedString(document.attributedText)
            currentSectionIndex = index
            requestedSectionIndex = index
            anchors = document.anchors
            loadedBookContent = false
            sectionRanges.removeAll()
            sectionIndices.removeAll()
            sectionAnchors.removeAll()
            updateDocumentLayout()
            applyAnnotations()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }

        private func preparePageTurn(direction: Int) -> ReaderPageTurn? {
            guard settings.flow.isPaging, let scrollView, let textView, let book,
                  book.spine.indices.contains(currentSectionIndex) else { return nil }
            let oldIndex = currentSectionIndex
            let oldLocation = firstVisibleCharacterLocation()
            let oldSelection = textView.selectedRange()
            let height = currentViewportHeight()
            let currentPage = Int((scrollView.contentView.bounds.origin.y / height).rounded())
            let targetPage = currentPage + direction
            var oldDocument: NativeChapterDocument?
            if targetPage >= 0, targetPage < textView.pageCount {
                scroll(to: CGFloat(targetPage) * height, animated: false)
            } else {
                let targetIndex = currentSectionIndex + direction
                guard book.spine.indices.contains(targetIndex) else { return nil }
                do {
                    oldDocument = try chapterDocument(at: oldIndex)
                    let document = try chapterDocument(at: targetIndex)
                    installPageChapter(document, at: targetIndex)
                    scroll(to: direction > 0 ? 0 : maximumScrollOffset(), animated: false)
                    logger.debug("翻页进入章节: section=\(targetIndex)")
                } catch {
                    logger.error("翻页加载失败: section=\(targetIndex), error=\(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            return ReaderPageTurn { [weak self] in
                guard let self else { return }
                if let oldDocument { self.installPageChapter(oldDocument, at: oldIndex) }
                self.scrollToCharacter(oldLocation, animated: false)
                self.textView?.setSelectedRange(oldSelection)
            }
        }

        private func seekWithinChapter(to fraction: Double, animated: Bool) {
            let count = max(1, textView?.pageCount ?? 1)
            let page = Int((min(1, max(0, fraction)) * Double(count - 1)).rounded())
            scroll(to: CGFloat(page) * currentViewportHeight(), animated: animated)
            reportProgress()
        }

        private func seek(to fraction: Double, animated: Bool) {
            let normalized = min(max(fraction, 0), 1)
            if settings.flow.isPaging,
               let book,
               !book.spine.isEmpty {
                let scaled = normalized * Double(book.spine.count)
                let targetIndex = min(book.spine.count - 1, Int(scaled))
                let localFraction = targetIndex == book.spine.count - 1
                    ? min(1, max(0, scaled - Double(targetIndex)))
                    : scaled - Double(targetIndex)
                updatingDocument = true
                defer { updatingDocument = false; reportProgress() }
                do {
                    if targetIndex != currentSectionIndex {
                        let document = try chapterDocument(at: targetIndex)
                        installPageChapter(document, at: targetIndex)
                    }
                    seekWithinChapter(to: localFraction, animated: animated)
                } catch {
                    logger.error("跳转阅读进度失败: section=\(targetIndex), error=\(error.localizedDescription, privacy: .public)")
                }
                return
            }
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

        private func ensureAdjacentChaptersLoaded() {
            guard !loadingAdjacentChapter,
                  loadedBookContent,
                  settings.flow.scrollScope == .book,
                  let book,
                  let scrollView,
                  loadedBookStartIndex >= 0,
                  loadedBookEndIndex >= 0 else { return }
            let maximum = maximumScrollOffset()
            let offset = scrollView.contentView.bounds.origin.y
            let threshold = max(280, scrollView.contentView.bounds.height * 0.8)
            if offset <= threshold, loadedBookStartIndex > book.spine.startIndex {
                loadAdjacentChapter(at: loadedBookStartIndex - 1, prepend: true)
            } else if offset >= maximum - threshold,
                      loadedBookEndIndex < book.spine.index(before: book.spine.endIndex) {
                loadAdjacentChapter(at: loadedBookEndIndex + 1, prepend: false)
            }
        }

        private func loadAdjacentChapter(at index: Int, prepend: Bool) {
            guard !loadingAdjacentChapter,
                  let book,
                  book.spine.indices.contains(index),
                  let textView,
                  let scrollView,
                  let storage = textView.textStorage else { return }
            loadingAdjacentChapter = true
            defer { loadingAdjacentChapter = false }
            do {
                let chapter = try loader.loadDocument(
                    book: book,
                    sectionIndex: index,
                    fontSize: settings.fontSize,
                    lineHeight: settings.lineHeight,
                    foreground: NativeReaderAppearance(theme: settings.theme).foreground
                )
                let identity = spineIdentity(book.spine[index])
                let separator = storage.length > 0
                    ? NSAttributedString(string: "\n\n")
                    : NSAttributedString()
                clearSpeechRange()
                if prepend {
                    let previousLocation = firstVisibleCharacterLocation()
                    let previousDocumentY = textView.documentY(forCharacter: previousLocation)
                    let previousViewportY = scrollView.contentView.bounds.origin.y
                    let insertion = NSMutableAttributedString(attributedString: chapter.attributedText)
                    insertion.append(separator)
                    let insertionLength = insertion.length
                    storage.insert(insertion, at: 0)
                    for key in Array(sectionRanges.keys) {
                        guard let range = sectionRanges[key] else { continue }
                        sectionRanges[key] = NSRange(
                            location: range.location + insertionLength,
                            length: range.length
                        )
                    }
                    for key in Array(anchors.keys) {
                        if let location = anchors[key] {
                            anchors[key] = location + insertionLength
                        }
                    }
                    sectionRanges[identity] = NSRange(
                        location: 0,
                        length: chapter.attributedText.length
                    )
                    sectionIndices[identity] = index
                    sectionAnchors[identity] = chapter.anchors
                    for (anchor, location) in chapter.anchors {
                        anchors[anchor] = location
                    }
                    loadedBookStartIndex = index
                    updateDocumentLayout()
                    if let previousDocumentY,
                       let nextDocumentY = textView.documentY(forCharacter: previousLocation + insertionLength) {
                        let viewportDistance = previousDocumentY - previousViewportY
                        scroll(to: nextDocumentY - viewportDistance, animated: false)
                    }
                } else {
                    if separator.length > 0 {
                        storage.append(separator)
                    }
                    let start = storage.length
                    storage.append(chapter.attributedText)
                    sectionRanges[identity] = NSRange(
                        location: start,
                        length: chapter.attributedText.length
                    )
                    sectionIndices[identity] = index
                    sectionAnchors[identity] = chapter.anchors
                    for (anchor, location) in chapter.anchors {
                        anchors[anchor] = start + location
                    }
                    loadedBookEndIndex = index
                    updateDocumentLayout()
                }
                applyAnnotations()
                speechBridge.refresh()
                logger.info("按需加载相邻章节: chapter=\(index + 1)/\(book.spine.count, privacy: .public), prepend=\(prepend, privacy: .public)")
            } catch {
                logger.error("按需加载章节失败: section=\(index), error=\(error.localizedDescription, privacy: .public)")
            }
        }

        private func scrollToEnd() {
            guard let scrollView else { return }
            let maximum = maximumScrollOffset()
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximum))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func reportProgress() {
            guard !isTornDown, !isRestoringPosition, !updatingDocument,
                  (scrollView as? ReaderScrollView)?.isPageTransitionActive != true,
                  let scrollView, let book else { return }
            ensureAdjacentChaptersLoaded()
            let maximum = maximumScrollOffset()
            let fraction = maximum > 0 ? scrollView.contentView.bounds.origin.y / maximum : 0
            let visibleLocation = firstVisibleCharacterLocation()
            if loadedBookContent,
               let visibleSection = sectionRanges.first(where: { NSLocationInRange(visibleLocation, $0.value) }),
               let sectionIndex = sectionIndices[visibleSection.key] {
                currentSectionIndex = sectionIndex
            }
            guard book.spine.indices.contains(currentSectionIndex) else { return }
            let identity = spineIdentity(book.spine[currentSectionIndex])
            let localLocation: Int
            let overallFraction: Double
            if loadedBookContent,
               let range = sectionRanges[identity] {
                localLocation = max(0, min(range.length - 1, visibleLocation - range.location))
                let loadedFraction = maximum > 0
                    ? Double(scrollView.contentView.bounds.origin.y / maximum)
                    : 0
                if loadedBookStartIndex >= 0,
                   loadedBookEndIndex >= loadedBookStartIndex {
                    let loadedSpan = loadedBookEndIndex - loadedBookStartIndex + 1
                    overallFraction = min(
                        1,
                        max(
                            0,
                            (Double(loadedBookStartIndex) + loadedFraction * Double(loadedSpan))
                                / Double(max(book.spine.count, 1))
                        )
                    )
                } else {
                    overallFraction = loadedFraction
                }
            } else if settings.flow.isPaging {
                localLocation = visibleLocation
                let page = Int((scrollView.contentView.bounds.origin.y / currentViewportHeight()).rounded())
                let count = max(1, textView?.pageCount ?? 1)
                let chapterFraction = count > 1
                    ? Double(page) / Double(count - 1)
                    : (currentSectionIndex == book.spine.count - 1 ? 1 : 0)
                overallFraction = (Double(currentSectionIndex) + chapterFraction) / Double(max(1, book.spine.count))
            } else {
                localLocation = visibleLocation
                overallFraction = fraction
            }
            let position = ReadingPosition(
                spineID: identity,
                characterOffset: localLocation,
                viewportOffset: textView?.viewportOffset(forCharacter: visibleLocation).map(Double.init)
            )
            reportPageInfo(offset: scrollView.contentView.bounds.origin.y)
            notifyProgress(min(1, max(0, overallFraction)), position: position)
        }

        private func reportPageInfo(offset: CGFloat) {
            guard settings.flow.isPaging else { return }
            let step = currentViewportHeight()
            let page = max(1, Int((offset / step).rounded()) + 1)
            let count = textView?.pageCount ?? 1
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown,
                      (self.scrollView as? ReaderScrollView)?.isPageTransitionActive != true else { return }
                self.onPageInfo(min(page, count), count)
            }
        }

        private func firstVisibleCharacterLocation() -> Int {
            if let location = textView?.visibleCharacterLocation() {
                return location
            }
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
