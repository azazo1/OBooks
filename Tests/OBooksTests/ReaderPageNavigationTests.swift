import AppKit
import XCTest
@testable import OBooks

@MainActor
final class ReaderPageNavigationTests: XCTestCase {
    func testOpeningSavedPositionKeepsPageAndAllowsFurtherTurns() async throws {
        let position = ReadingPosition(spineID: "chapter-0", characterOffset: 1500)
        let reader = try Fixture(position: position)
        defer { reader.close() }
        let restoredOffset = try XCTUnwrap(reader.textView.pageOffset(forCharacter: position.characterOffset))
        XCTAssertGreaterThan(restoredOffset, 0)
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, restoredOffset)
        reader.textView.setFrameSize(reader.scrollView.contentSize)
        try await Task.sleep(for: .milliseconds(30))
        reader.update()
        reader.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, restoredOffset)

        for page in 1...2 {
            XCTAssertTrue(reader.scrollView.turnPage(direction: 1))
            reader.scrollView.prepareForProgrammaticScroll()
            try await Task.sleep(for: .milliseconds(30))
            reader.update()
            XCTAssertEqual(reader.scrollView.contentView.bounds.minY, restoredOffset + CGFloat(page) * 600)
            XCTAssertEqual(reader.positions.last?.characterOffset, reader.textView.visibleCharacterLocation())
        }
    }

    func testOpeningSavedChapterScrollPositionDoesNotDrift() async throws {
        try await assertScrollPositionSurvivesReopening(scope: .chapter)
    }

    func testBookmarkReturnsToFixedPositionAfterMovingAcrossChapters() async throws {
        for flow in [
            ReaderFlowMode.paging(orientation: .horizontal, columns: .single),
            .scrolling(scope: .chapter),
            .scrolling(scope: .book)
        ] {
            let reader = try Fixture(flow: flow)
            defer { reader.close() }
            reader.scrollView.scroll(to: flow.isPaging ? 1200 : 1407.25, animated: false)
            try await Task.sleep(for: .milliseconds(30))
            let position = try XCTUnwrap(reader.positions.last)
            let bookmark = ReaderBookmark(position: position, title: "第一章", progressFraction: 0.1)
            let offset = reader.scrollView.contentView.bounds.minY

            reader.scrollView.scroll(to: offset + 600, animated: false)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertFalse(bookmark.matches(try XCTUnwrap(reader.positions.last)))
            reader.section = 2
            reader.pendingPosition = ReadingPosition(spineID: "chapter-2", characterOffset: 900)
            reader.update(flow: flow)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(reader.positions.last?.spineID, "chapter-2")

            reader.section = 0
            reader.pendingPosition = bookmark.position
            reader.update(flow: flow)
            try await Task.sleep(for: .milliseconds(30))

            XCTAssertEqual(bookmark.position, position)
            XCTAssertEqual(reader.positions.last?.spineID, bookmark.position.spineID)
            XCTAssertEqual(reader.positions.last?.characterOffset, bookmark.position.characterOffset)
            XCTAssertEqual(reader.scrollView.contentView.bounds.minY, offset, accuracy: 0.5)
        }
    }

    func testOpeningSavedBookScrollPositionDoesNotDrift() async throws {
        try await assertScrollPositionSurvivesReopening(scope: .book)
    }

    private func assertScrollPositionSurvivesReopening(scope: ReaderScrollScope) async throws {
        let flow = ReaderFlowMode.scrolling(scope: scope)
        let firstReader = try Fixture(flow: flow)
        firstReader.scrollView.scroll(to: 1407.25, animated: false)
        try await Task.sleep(for: .milliseconds(30))
        let expectedOffset = firstReader.scrollView.contentView.bounds.minY
        var savedPosition = try XCTUnwrap(firstReader.positions.last)
        firstReader.close()

        for _ in 0..<3 {
            let reader = try Fixture(position: savedPosition, flow: flow)
            defer { reader.close() }
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(reader.scrollView.contentView.bounds.minY, expectedOffset, accuracy: 0.5)
            savedPosition = try XCTUnwrap(reader.positions.last)
        }
    }

    func testChapterBoundaryAndReverseTurnRestoreExactPage() async throws {
        let reader = try Fixture()
        defer { reader.close() }
        XCTAssertFalse(reader.scrollView.turnPage(direction: -1, animated: false))
        let firstText = reader.textView.string
        let pages = reader.textView.pageCount
        XCTAssertGreaterThan(pages, 1)
        for page in 1..<pages {
            XCTAssertTrue(reader.scrollView.turnPage(direction: 1, animated: false))
            XCTAssertEqual(reader.scrollView.contentView.bounds.minY, CGFloat(page) * 600)
        }
        let lastLocation = reader.textView.visibleCharacterLocation()
        XCTAssertTrue(reader.scrollView.turnPage(direction: 1, animated: false))
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 0)
        XCTAssertEqual(reader.textView.pageCount, 1)
        XCTAssertTrue(reader.scrollView.turnPage(direction: -1, animated: false))
        XCTAssertEqual(reader.textView.string, firstText)
        XCTAssertEqual(reader.textView.visibleCharacterLocation(), lastLocation)
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, CGFloat(pages - 1) * 600)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reader.positions.last?.spineID, "chapter-0")
    }

    func testCancelledChapterSwipeDoesNotPublishPreviewAndIgnoresMomentum() async throws {
        let reader = try Fixture()
        defer { reader.close() }
        reader.scrollView.scroll(to: CGFloat(reader.textView.pageCount - 1) * 600, animated: false)
        try await Task.sleep(for: .milliseconds(30))
        let text = reader.textView.string
        let location = reader.textView.visibleCharacterLocation()
        reader.positions.removeAll()
        reader.scrollView.handlePageScroll(with: try wheel(delta: -30, phase: .began, time: 1))
        XCTAssertTrue(reader.scrollView.isPageTransitionActive)
        XCTAssertEqual(reader.textView.pageCount, 1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(reader.positions.isEmpty)
        reader.scrollView.handlePageScroll(with: try wheel(delta: 0, phase: .cancelled, time: 1.1))
        reader.scrollView.prepareForProgrammaticScroll()
        XCTAssertFalse(reader.scrollView.isPageTransitionActive)
        XCTAssertFalse(reader.textView.isHidden)
        XCTAssertEqual(reader.textView.string, text)
        XCTAssertEqual(reader.textView.visibleCharacterLocation(), location)
        reader.scrollView.handlePageScroll(with: try wheel(delta: -300, phase: [], momentum: .began, time: 1.2))
        XCTAssertEqual(reader.textView.visibleCharacterLocation(), location)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reader.positions.last?.spineID, "chapter-0")
    }

    func testRapidTurnsCleanUpTransitionViews() throws {
        let reader = try Fixture()
        defer { reader.close() }
        XCTAssertTrue(reader.scrollView.turnPage(direction: 1))
        XCTAssertTrue(reader.scrollView.turnPage(direction: 1))
        reader.scrollView.prepareForProgrammaticScroll()
        XCTAssertFalse(reader.textView.isHidden)
        XCTAssertFalse(reader.scrollView.subviews.contains { $0 is NSImageView })
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 1200)
    }

    func testResizeAndFontChangeKeepReadingAnchorOnVisiblePage() async throws {
        let reader = try Fixture()
        defer { reader.close() }
        XCTAssertTrue(reader.scrollView.turnPage(direction: 1, animated: false))
        let location = try XCTUnwrap(reader.textView.visibleCharacterLocation())
        reader.scrollView.setFrameSize(NSSize(width: 760, height: 720))
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, reader.textView.pageOffset(forCharacter: location))
        XCTAssertEqual(reader.textView.frame.height, CGFloat(reader.textView.pageCount) * 720)
        let resizedLocation = try XCTUnwrap(reader.textView.visibleCharacterLocation())
        reader.update(fontSize: 24)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, reader.textView.pageOffset(forCharacter: resizedLocation))
        XCTAssertFalse(reader.positions.isEmpty)
    }

    func testSeekingAcrossChaptersSnapsToLastPageAndStopsAtBookEnd() async throws {
        let reader = try Fixture()
        defer { reader.close() }
        reader.coordinator.execute(.seek(1, animated: false))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(reader.positions.last?.spineID, "chapter-2")
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, CGFloat(reader.textView.pageCount - 1) * 600)
        XCTAssertFalse(reader.scrollView.turnPage(direction: 1, animated: false))
    }

    func testDirectoryNavigationToEarlierChapterStartsAtBeginning() throws {
        let reader = try Fixture()
        defer { reader.close() }
        reader.section = 2
        reader.update()
        reader.section = 0
        reader.update()
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 0)
    }

    func testBookScrollKeepsViewportWhenPrependingChapter() async throws {
        let reader = try Fixture()
        defer { reader.close() }
        reader.section = 1
        reader.update(flow: .scrolling(scope: .book))
        try await Task.sleep(for: .milliseconds(30))

        let marker = "中文阅读与 English words 12345."
        let text = reader.textView.string as NSString
        let chapterStart = text.range(of: marker, options: .backwards)
        XCTAssertNotEqual(chapterStart.location, NSNotFound)
        let chapterStartY = try XCTUnwrap(reader.textView.documentY(forCharacter: chapterStart.location))
        let viewportOffset = reader.scrollView.contentView.bounds.origin.y
        XCTAssertEqual(chapterStartY - viewportOffset, 64, accuracy: 1)
    }

    func testVerticalSwipeMovesBothPagesWithTheGesture() throws {
        let reader = try Fixture()
        defer { reader.close() }
        reader.update(flow: .paging(orientation: .vertical, columns: .double))
        reader.scrollView.turnPage(direction: 1, animated: false)
        for direction: Int32 in [1, -1] {
            reader.scrollView.handlePageScroll(with: try wheel(delta: 0, verticalDelta: -60 * direction, phase: .began, time: 1))
            let images = reader.scrollView.subviews.compactMap { $0 as? NSImageView }
            XCTAssertEqual(images.count, 2)
            if images.count == 2 {
                let upward: CGFloat = reader.scrollView.isFlipped ? -1 : 1
                XCTAssertEqual(images[0].frame.minY, 60 * upward * CGFloat(direction), accuracy: 0.01)
                XCTAssertEqual(images[1].frame.minY, -540 * upward * CGFloat(direction), accuracy: 0.01)
            }
            reader.scrollView.prepareForProgrammaticScroll()
            XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 600)
        }
    }

    func testSpeechCrossChapterKeepsAudioAndDisablesPreviewUntilStopped() async throws {
        for flow: ReaderFlowMode in [.paging(orientation: .horizontal, columns: .double), .scrolling(scope: .chapter)] {
            let engine = FakeSpeechEngine()
            let session = SpeechSession(engine: engine)
            let reader = try Fixture(flow: flow, speech: session)
            defer { reader.close() }
            session.start(section: 1)
            for _ in 0..<100 where engine.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertEqual(session.state, .playing)
            XCTAssertFalse(reader.textView.allowsImagePreview)
            XCTAssertTrue(reader.scrollView.isPageTransitionActive || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            reader.scrollView.prepareForProgrammaticScroll()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(reader.positions.last?.spineID, "chapter-1")
            XCTAssertFalse(reader.textView.isHidden)
            session.pause()
            XCTAssertFalse(reader.textView.allowsImagePreview)
            reader.section = 2
            reader.update(flow: flow)
            XCTAssertEqual(session.sectionIndex, 1)
            XCTAssertEqual(session.state, .paused)
            reader.coordinator.execute(.revealSpeech)
            reader.scrollView.prepareForProgrammaticScroll()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(reader.positions.last?.spineID, "chapter-1")
            session.stop()
            XCTAssertTrue(reader.textView.allowsImagePreview)
        }
    }

    func testSpeechSurvivesReflowAndMapsPositionAfterPrepending() async throws {
        let engine = FakeSpeechEngine()
        let session = SpeechSession(engine: engine)
        let flow = ReaderFlowMode.scrolling(scope: .book)
        let reader = try Fixture(position: ReadingPosition(spineID: "chapter-1", characterOffset: 0), flow: flow, speech: session)
        defer { reader.close() }
        session.start(section: 1)
        for _ in 0..<100 where engine.calls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        reader.scrollView.prepareForProgrammaticScroll()
        let originalPosition = try XCTUnwrap(session.position)
        reader.scrollView.scroll(to: 0, animated: false)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertGreaterThan(reader.textView.string.utf16.count, 100)
        reader.section = 1
        reader.update(fontSize: 24, flow: flow)
        XCTAssertEqual(session.state, .playing)
        XCTAssertEqual(session.position, originalPosition)
        XCTAssertEqual(engine.calls.count, 1)
        let call = try XCTUnwrap(engine.calls.last)
        engine.onEvent?(.range(call.id, NSRange(location: 0, length: 2)))
        reader.scrollView.prepareForProgrammaticScroll()
        XCTAssertEqual(session.position?.spineID, "chapter-1")
        XCTAssertEqual(session.position?.range.location, 0)
    }

    func testArrowKeysTurnPagesInPagingMode() throws {
        let reader = try Fixture()
        defer { reader.close() }
        reader.textView.keyDown(with: try arrow(ReaderKeyNavigation.rightArrow))
        reader.scrollView.prepareForProgrammaticScroll()
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 600)
        reader.textView.keyDown(with: try arrow(ReaderKeyNavigation.leftArrow))
        reader.scrollView.prepareForProgrammaticScroll()
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 0)
        reader.textView.keyDown(with: try arrow(ReaderKeyNavigation.downArrow))
        reader.scrollView.prepareForProgrammaticScroll()
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 600)
        reader.textView.keyDown(with: try arrow(ReaderKeyNavigation.upArrow))
        reader.scrollView.prepareForProgrammaticScroll()
        XCTAssertEqual(reader.scrollView.contentView.bounds.minY, 0)
    }

    func testArrowKeysScrollInScrollingMode() async throws {
        let reader = try Fixture(flow: .scrolling(scope: .chapter))
        defer { reader.close() }
        try await Task.sleep(for: .milliseconds(30))
        reader.textView.keyDown(with: try arrow(ReaderKeyNavigation.downArrow))
        XCTAssertGreaterThan(try XCTUnwrap(reader.scrollView.scrollTargetY), 0)
        reader.textView.keyDown(with: try arrow(ReaderKeyNavigation.rightArrow))
        XCTAssertGreaterThan(try XCTUnwrap(reader.scrollView.scrollTargetY), 0)
    }

    private func arrow(_ code: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code
        ))
    }

    private func wheel(delta: Int32, verticalDelta: Int32 = 0, phase: NSEvent.Phase, momentum: NSEvent.Phase = [], time: Double) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: verticalDelta, wheel2: delta, wheel3: 0
        ))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        event.timestamp = UInt64(time * 1_000_000_000)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    @MainActor
    private final class Fixture {
        let coordinator: NativeReaderView.Coordinator
        let scrollView = ReaderScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let textView = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let window: NSWindow
        let book: BookSummary
        var section = 0
        var positions: [ReadingPosition] = []
        var pendingPosition: ReadingPosition?

        init(
            position: ReadingPosition? = nil,
            flow: ReaderFlowMode = .paging(orientation: .horizontal, columns: .single),
            speech: SpeechSession? = nil
        ) throws {
            coordinator = NativeReaderView.Coordinator(speech: speech)
            _ = NSApplication.shared
            window = NSWindow(contentRect: scrollView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scrollView
            pendingPosition = position
            book = BookSummary(
                id: UUID(), title: "分页测试", authors: [], sortTitle: "test",
                sourceFileName: "test.epub", folderName: "pagination-test-" + UUID().uuidString,
                coverPath: nil,
                spine: (0..<3).map { EPUBSpineItem(id: "chapter-\($0)", href: "\($0).xhtml", title: "\($0)", linear: true) },
                toc: [], progressFraction: 0, lastOpenedAt: nil, importedAt: Date()
            )
            try FileManager.default.createDirectory(at: book.folderURL, withIntermediateDirectories: true)
            for index in 0..<3 {
                let paragraphs = String(repeating: "<p>中文阅读与 English words 12345.</p>", count: index == 1 ? 1 : 120)
                try Data("<html><body>\(paragraphs)</body></html>".utf8)
                    .write(to: book.folderURL.appendingPathComponent("\(index).xhtml"))
            }
            scrollView.wantsLayer = true
            scrollView.layer?.masksToBounds = true
            scrollView.borderType = .noBorder
            scrollView.contentView.wantsLayer = true
            textView.wantsLayer = true
            textView.isEditable = false
            textView.isSelectable = true
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.minSize = NSSize(width: 0, height: 600)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.containerSize = NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.lineFragmentPadding = 0
            scrollView.documentView = textView
            coordinator.attach(scrollView: scrollView, textView: textView)
            update(flow: flow)
        }

        func update(fontSize: Double = 18, flow: ReaderFlowMode = .paging(orientation: .horizontal, columns: .single)) {
            coordinator.update(
                book: book, sectionIndex: section, pendingAnchor: nil, pendingPosition: pendingPosition,
                pendingPositionAnimated: false, theme: .paper,
                flow: flow,
                fontSize: fontSize, lineHeight: 1.7, margin: 56, annotations: [],
                onProgress: { [weak self] _, position in self?.positions.append(position) },
                onBoundary: { _ in }, onSpeakingChanged: { _ in }, onAnnotation: { _, _, _ in },
                onNoteRequest: { _, _ in },
                onNavigate: { [weak self] index, _ in
                    self?.section = index
                    self?.update()
                },
                onAnchorConsumed: {}, onPositionConsumed: { [weak self] in self?.pendingPosition = nil }
            )
            coordinator.loadSectionIfNeeded()
        }

        func close() {
            coordinator.teardown()
            window.close()
            try? FileManager.default.removeItem(at: book.folderURL)
        }
    }
}
