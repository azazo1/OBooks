import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
private final class ReaderProgressState: ObservableObject {
    @Published private(set) var value = 0.0
    private var persistenceTask: Task<Void, Never>?
    private var latestPersistValue: Double?
    private var latestPersistPosition: ReadingPosition?
    private var persistenceRevision = 0
    private var persistencePending = false
    private var onPersist: ((Double, ReadingPosition) -> Void)?

    func configure(onPersist: @escaping (Double, ReadingPosition) -> Void) {
        self.onPersist = onPersist
    }

    func setInitialValue(_ value: Double) {
        self.value = min(max(value, 0), 1)
    }

    func update(_ value: Double, persistValue: Double, position: ReadingPosition) {
        let normalizedValue = min(max(value, 0), 1)
        let normalizedPersistValue = min(max(persistValue, 0), 1)
        let valueChanged = abs(self.value - normalizedValue) > 0.0001
        let persistChanged = latestPersistValue != normalizedPersistValue
        let positionChanged = latestPersistPosition != position
        latestPersistValue = normalizedPersistValue
        latestPersistPosition = position
        if valueChanged {
            self.value = normalizedValue
        }
        guard valueChanged || persistChanged || positionChanged else { return }
        persistenceRevision &+= 1
        persistencePending = true
        guard persistenceTask == nil else { return }
        persistenceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                let revision = self.persistenceRevision
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                guard revision == self.persistenceRevision else { continue }
                self.persistencePending = false
                self.persistenceTask = nil
                if let persistValue = self.latestPersistValue,
                    let position = self.latestPersistPosition
                {
                    self.onPersist?(persistValue, position)
                }
                return
            }
        }
    }

    func flush() {
        persistenceTask?.cancel()
        persistenceTask = nil
        if persistencePending,
            let persistValue = latestPersistValue,
            let position = latestPersistPosition
        {
            persistencePending = false
            onPersist?(persistValue, position)
        }
    }
}

private enum ReaderPanel: Equatable {
    case toc
    case bookmarks
    case highlights
    case search
    case settings
    case flow

    var title: String {
        switch self {
        case .toc: return "目录"
        case .bookmarks: return "书签"
        case .highlights: return "高亮标记和笔记"
        case .search: return "搜索"
        case .settings: return "主题与设置"
        case .flow: return "浏览模式"
        }
    }

    var isLeading: Bool {
        switch self {
        case .toc, .bookmarks: return true
        case .highlights, .search, .settings, .flow: return false
        }
    }
}

struct ReaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appModel: AppModel

    let book: BookSummary
    @State private var controller = ReaderController()
    @State private var sectionIndex = 0
    @State private var pendingAnchor: String?
    @State private var pendingPosition: ReadingPosition?
    @State private var pendingPositionAnimated = false
    @State private var currentPosition: ReadingPosition?
    @State private var jumpBackPosition: ReadingPosition?
    @State private var progressState = ReaderProgressState()
    @State private var theme: ReadingTheme = .focus
    @State private var fontSize = 18.0
    @State private var lineHeight = 1.7
    @State private var margin = 56.0
    @State private var flow: ReaderFlowMode = .scrolling(scope: .chapter)
    @State private var pageNumber = 1
    @State private var pageCount = 1
    @State private var activePanel: ReaderPanel?
    @State private var isBookmarked = false
    @State private var searchQuery = ""
    @State private var isSpeaking = false
    @State private var chromeVisible = true
    @State private var isPointerNearChrome = false
    @State private var hideChromeTask: Task<Void, Never>?
    @State private var annotations: [ReaderAnnotation] = []
    @State private var noteContext = ""
    @State private var noteText = ""
    @State private var noteRange = NSRange(location: NSNotFound, length: 0)
    @State private var isEditingNote = false

    init(book: BookSummary) {
        self.book = book
        let initialSectionIndex = Self.initialSectionIndex(for: book)
        _sectionIndex = State(initialValue: initialSectionIndex)
        _flow = State(
            initialValue: ReaderFlowMode(
                preferenceValue: UserDefaults.standard.string(forKey: "reader.browsingMode") ?? ""
            ) ?? .scrolling(scope: .chapter)
        )
        _pendingPosition = State(initialValue: Self.initialReadingPosition(for: book))
        _currentPosition = State(
            initialValue: Self.initialReadingPosition(for: book)
                ?? Self.defaultReadingPosition(for: book, sectionIndex: initialSectionIndex)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            chromeBackground.ignoresSafeArea()

            NativeReaderView(
                book: book,
                sectionIndex: $sectionIndex,
                pendingAnchor: $pendingAnchor,
                pendingPosition: $pendingPosition,
                pendingPositionAnimated: $pendingPositionAnimated,
                theme: theme,
                flow: flow,
                fontSize: fontSize,
                lineHeight: lineHeight,
                margin: margin,
                annotations: annotations,
                controller: controller,
                onProgress: { value, position in
                    currentPosition = position
                    let count = Double(max(book.spine.count, 1))
                    let currentIndex =
                        book.spine.firstIndex { spineIdentity($0) == position.spineID }
                        ?? sectionIndex
                    let overall = flow.scrollScope == .book || flow.isPaging
                        ? min(1, max(0, value))
                        : min(1, Double(currentIndex) / count + value / count)
                    if flow.scrollScope == .book || flow.isPaging {
                        sectionIndex = currentIndex
                    }
                    let displayValue = flow.scrollScope == .chapter && !flow.isPaging ? value : overall
                    progressState.update(displayValue, persistValue: overall, position: position)
                },
                onPageInfo: { number, count in
                    pageNumber = number
                    pageCount = count
                },
                onBoundary: moveSection,
                onSpeakingChanged: { value in
                    isSpeaking = value
                },
                onAnnotation: { text, kind, range in
                    guard !text.isEmpty else { return }
                    annotations.insert(
                        ReaderAnnotation(
                            text: text, kind: kind, sectionIndex: sectionIndex, range: range),
                        at: 0
                    )
                },
                onNoteRequest: { text, range in
                    noteContext = text
                    noteRange = range
                    noteText = ""
                    isEditingNote = true
                    keepChromeVisible()
                },
                onNavigate: { index, anchor in
                    registerJump()
                    navigateTo(sectionIndex: index, anchor: anchor)
                },
                onAnchorConsumed: {
                    pendingAnchor = nil
                    pendingPosition = nil
                    pendingPositionAnimated = false
                },
                onPositionConsumed: {
                    pendingPosition = nil
                    pendingPositionAnimated = false
                }
            )

            topBar

            if let activePanel {
                panelView(activePanel)
            }
        }
        .overlay(alignment: .bottom) {
            readerFooter
        }
        .overlay(alignment: .bottom) {
            if flow.isPaging {
                Text("\(pageNumber)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.bottom, chromeVisible ? 58 : 18)
                    .accessibilityLabel("第 \(pageNumber) 页, 共 \(pageCount) 页")
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if jumpBackPosition != nil {
                jumpBackButton
            }
        }
        .overlay {
            ReaderMouseTracker(chromeVisible: chromeVisible, edgeThreshold: 88) { isNear in
                updateChromeProximity(isNear)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if isEditingNote {
                noteEditor
                    .padding(.trailing, 24)
                    .padding(.bottom, 58)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .ignoresSafeArea(.container, edges: .top)
        .background(chromeBackground)
        .onAppear {
            progressState.configure { fraction, position in
                appModel.updateProgress(bookID: book.id, fraction: fraction, position: position)
            }
            progressState.setInitialValue(book.progressFraction)
            if colorScheme == .light && theme == .focus {
                theme = .paper
            }
            scheduleChromeHide(after: .seconds(1.4))
        }
        .onChange(of: flow) { _, newFlow in
            UserDefaults.standard.set(newFlow.preferenceValue, forKey: "reader.browsingMode")
        }
        .onDisappear {
            hideChromeTask?.cancel()
            progressState.flush()
        }
        .onExitCommand {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 13) {
                readerButton(systemName: "list.bullet", help: "显示目录", panel: .toc)
                readerButton(systemName: "books.vertical", help: "显示书签", panel: .bookmarks)
                readerButton(systemName: "note.text", help: "显示高亮和笔记", panel: .highlights)
            }
            .frame(width: 136, alignment: .leading)

            Spacer(minLength: 12)

            Text(book.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)

            Spacer(minLength: 12)

            HStack(spacing: 15) {
                readerButton(label: "大", help: "打开阅读设置", panel: .settings)
                readerButton(systemName: "book.pages", help: "打开浏览模式", panel: .flow)
                readerButton(systemName: "magnifyingglass", help: "搜索书籍", panel: .search)
                Button {
                    isBookmarked.toggle()
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isBookmarked ? OBooksPalette.accent : .white.opacity(0.78))
                        .frame(width: 22, height: 26)
                }
                .buttonStyle(OBooksIconButtonStyle())
                .help(isBookmarked ? "移除本章书签" : "添加本章书签")
            }
            .frame(width: 136, alignment: .trailing)
        }
        .padding(.leading, 82)
        .padding(.trailing, 22)
        .frame(height: 52)
        .background(chromeBackground.opacity(colorScheme == .dark ? 0.92 : 0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .opacity(chromeVisible ? 1 : 0)
        .allowsHitTesting(chromeVisible)
        .animation(.easeOut(duration: 0.18), value: chromeVisible)
    }

    private func readerButton(systemName: String, help: String, panel: ReaderPanel) -> some View {
        Button {
            togglePanel(panel)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(activePanel == panel ? OBooksPalette.accent : .white.opacity(0.78))
                .frame(width: 22, height: 26)
        }
        .buttonStyle(OBooksIconButtonStyle())
        .help(help)
    }

    private func readerButton(label: String, help: String, panel: ReaderPanel) -> some View {
        Button {
            togglePanel(panel)
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(activePanel == panel ? OBooksPalette.accent : .white.opacity(0.78))
                .frame(width: 22, height: 26)
        }
        .buttonStyle(OBooksIconButtonStyle())
        .help(help)
    }

    @ViewBuilder
    private func panelView(_ panel: ReaderPanel) -> some View {
        panelContent(panel)
            .padding(.top, 52)
            .frame(
                maxWidth: .infinity, maxHeight: .infinity,
                alignment: panel.isLeading ? .topLeading : .topTrailing)
    }

    @ViewBuilder
    private func panelContent(_ panel: ReaderPanel) -> some View {
        switch panel {
        case .toc:
            ReaderPanelSurface(title: panel.title, width: 286) {
                tocContent
            }
        case .bookmarks:
            ReaderPanelSurface(title: panel.title, width: 286) {
                bookmarkContent
            }
        case .highlights:
            ReaderPanelSurface(title: panel.title, width: 316) {
                highlightsContent
            }
        case .search:
            ReaderPanelSurface(title: panel.title, width: 286) {
                searchContent
            }
        case .settings:
            ReaderPanelSurface(title: panel.title, width: 306) {
                settingsContent
            }
        case .flow:
            ReaderPanelSurface(title: panel.title, width: 286) {
                flowControls
            }
        }
    }

    private var tocContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if book.toc.isEmpty {
                    panelEmpty(icon: "list.bullet", title: "没有目录", message: "这本书没有提供目录")
                } else {
                    ForEach(flatten(book.toc)) { entry in
                        Button {
                            navigateTo(href: entry.item.href)
                        } label: {
                            Text(entry.item.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, CGFloat(14 + entry.depth * 12))
                                .padding(.trailing, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 9)
        }
        .scrollIndicators(.hidden)
    }

    private var bookmarkContent: some View {
        VStack(spacing: 0) {
            if isBookmarked {
                Button {
                    activePanel = nil
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(OBooksPalette.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentChapterTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                            Text("当前位置")
                                .font(.system(size: 11))
                                .foregroundStyle(OBooksPalette.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            } else {
                panelEmpty(icon: "bookmark", title: "无书签", message: "点击顶栏书签图标添加")
            }
            Spacer()
        }
    }

    private var highlightsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if annotations.isEmpty {
                    panelEmpty(icon: "highlighter", title: "无高亮", message: "选中文字后可在这里查看")
                } else {
                    ForEach(annotations) { annotation in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                annotation.kind == "note" ? "笔记" : "高亮",
                                systemImage: annotation.kind == "note" ? "note.text" : "highlighter"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(OBooksPalette.accent)
                            Text(annotation.text)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(OBooksPalette.secondaryText)
                TextField("输入一个字词或页码", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(OBooksPalette.secondaryText)
                    }
                    .buttonStyle(OBooksIconButtonStyle(size: 26, cornerRadius: 7))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            }

            HStack {
                Text("最近搜索")
                Spacer()
                Button("清除") { searchQuery = "" }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OBooksPalette.secondaryText)

            if searchQuery.isEmpty {
                Text("输入关键词开始搜索")
                    .font(.system(size: 12))
                    .foregroundStyle(OBooksPalette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("搜索功能将在下一版连接到章节索引")
                    .font(.system(size: 12))
                    .foregroundStyle(OBooksPalette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                sizeButton(title: "小", value: 16)
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1, height: 16)
                sizeButton(title: "大", value: 20)
            }
            .frame(height: 27)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ], spacing: 10
            ) {
                ForEach(ReadingTheme.allCases) { item in
                    themeButton(item)
                }
            }

            Button {
                fontSize = 18
                lineHeight = 1.7
                margin = 56
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                    Text("自定义")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    private var flowControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                flowButton(title: "滚动", selected: flow.scrollScope != nil) {
                    flow = .scrolling(scope: flow.scrollScope ?? .chapter)
                }
                flowButton(title: "翻页", selected: flow.isPaging) {
                    flow = .paging(
                        orientation: flow.pageOrientation ?? .horizontal,
                        columns: flow.pageColumns
                    )
                }
            }
            if let scope = flow.scrollScope {
                HStack(spacing: 6) {
                    ForEach(ReaderScrollScope.allCases) { item in
                        flowButton(title: item.label, selected: scope == item) {
                            flow = .scrolling(scope: item)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(ReaderPageOrientation.allCases) { item in
                        flowButton(
                            title: item.label,
                            selected: flow.pageOrientation == item
                        ) {
                            flow = .paging(orientation: item, columns: flow.pageColumns)
                        }
                    }
                    ForEach(ReaderPageColumns.allCases) { item in
                        flowButton(title: item.label, selected: flow.pageColumns == item) {
                            flow = .paging(
                                orientation: flow.pageOrientation ?? .horizontal,
                                columns: item
                            )
                        }
                    }
                }
            }
        }
    }

    private func flowButton(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? .white : OBooksPalette.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    selected ? OBooksPalette.accent.opacity(0.68) : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private func sizeButton(title: String, value: Double) -> some View {
        Button {
            fontSize = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(abs(fontSize - value) < 0.1 ? .white : OBooksPalette.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    abs(fontSize - value) < 0.1 ? Color.white.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func themeButton(_ item: ReadingTheme) -> some View {
        Button {
            theme = item
        } label: {
            VStack(spacing: 3) {
                Text("大")
                    .font(.system(size: 20, weight: .semibold))
                Text(item.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(themeForeground(item))
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(themeBackground(item), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        theme == item ? Color.white.opacity(0.92) : Color.white.opacity(0.09),
                        lineWidth: theme == item ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var readerFooter: some View {
        ReaderFooter(
            progressState: progressState,
            isSpeaking: isSpeaking,
            flow: flow,
            chromeBackground: chromeBackground,
            colorScheme: colorScheme,
            chromeVisible: chromeVisible,
            controller: controller,
            onSeekStarted: registerJump,
            onSeek: { x, width, animated in
                seekProgress(at: x, width: width, animated: animated)
            }
        )
    }

    private var jumpBackButton: some View {
        Button {
            undoJump()
        } label: {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .buttonStyle(OBooksIconButtonStyle(size: 30, cornerRadius: 15))
        .help("返回跳转前位置")
        .padding(.leading, 20)
        .padding(.bottom, 14)
        .opacity(chromeVisible ? 1 : 0)
        .allowsHitTesting(chromeVisible)
        .animation(.easeOut(duration: 0.18), value: chromeVisible)
        .transition(.opacity)
    }

    private func seekProgress(at x: CGFloat, width: CGFloat, animated: Bool) {
        let normalizedX = min(max(x / max(width, 1), 0), 1)
        controller.send(.seek(Double(normalizedX), animated: animated))
        keepChromeVisible()
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("添加笔记")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    isEditingNote = false
                    scheduleChromeHide(after: .milliseconds(650))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(OBooksIconButtonStyle(size: 28, cornerRadius: 7))
            }
            Text(noteContext)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            TextEditor(text: $noteText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(width: 270, height: 82)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            Button("保存笔记") {
                guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    noteRange.location != NSNotFound,
                    noteRange.length > 0
                else { return }
                annotations.insert(
                    ReaderAnnotation(
                        text: noteText, kind: "note", sectionIndex: sectionIndex, range: noteRange),
                    at: 0
                )
                isEditingNote = false
                scheduleChromeHide(after: .milliseconds(650))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private var chromeBackground: Color {
        colorScheme == .dark ? .black : Color(nsColor: .windowBackgroundColor)
    }

    private var currentChapterTitle: String {
        guard book.spine.indices.contains(sectionIndex) else { return "当前位置" }
        return book.spine[sectionIndex].title
    }

    private static func initialSectionIndex(for book: BookSummary) -> Int {
        if let position = book.readingPosition,
            let index = book.spine.firstIndex(where: { Self.spineIdentity($0) == position.spineID })
        {
            return index
        }
        guard !book.spine.isEmpty else { return 0 }
        return min(book.spine.count - 1, Int(book.progressFraction * Double(book.spine.count)))
    }

    private static func initialReadingPosition(for book: BookSummary) -> ReadingPosition? {
        guard let position = book.readingPosition,
            book.spine.contains(where: { Self.spineIdentity($0) == position.spineID })
        else { return nil }
        return position
    }

    private static func defaultReadingPosition(
        for book: BookSummary,
        sectionIndex: Int
    ) -> ReadingPosition? {
        guard book.spine.indices.contains(sectionIndex) else { return nil }
        return ReadingPosition(
            spineID: spineIdentity(book.spine[sectionIndex]),
            characterOffset: 0
        )
    }

    private static func spineIdentity(_ item: EPUBSpineItem) -> String {
        item.id.isEmpty ? item.href : item.id
    }

    private func spineIdentity(_ item: EPUBSpineItem) -> String {
        Self.spineIdentity(item)
    }

    private func keepChromeVisible() {
        chromeVisible = true
        hideChromeTask?.cancel()
    }

    private func updateChromeProximity(_ isNear: Bool) {
        isPointerNearChrome = isNear
        if isNear {
            keepChromeVisible()
        } else {
            scheduleChromeHide(after: .milliseconds(650))
        }
    }

    private func scheduleChromeHide(after delay: Duration) {
        hideChromeTask?.cancel()
        guard activePanel == nil, !isEditingNote, !isPointerNearChrome else { return }
        hideChromeTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, activePanel == nil, !isEditingNote, !isPointerNearChrome else {
                return
            }
            chromeVisible = false
        }
    }

    private func togglePanel(_ panel: ReaderPanel) {
        activePanel = activePanel == panel ? nil : panel
        if activePanel == nil {
            scheduleChromeHide(after: .milliseconds(650))
        } else {
            keepChromeVisible()
        }
    }

    private func moveSection(_ direction: Int) {
        let next = sectionIndex + (direction > 0 ? 1 : -1)
        guard book.spine.indices.contains(next) else { return }
        registerJump()
        sectionIndex = next
        progressState.setInitialValue(direction > 0 ? 0 : 1)
    }

    private func navigateTo(href: String) {
        guard let index = sectionIndex(for: href) else { return }
        registerJump()
        navigateTo(
            sectionIndex: index,
            anchor: href.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)
        )
    }

    private func navigateTo(sectionIndex index: Int, anchor: String?) {
        sectionIndex = index
        pendingAnchor = anchor
        activePanel = nil
        keepChromeVisible()
    }

    private func registerJump() {
        guard let currentPosition else { return }
        jumpBackPosition = currentPosition
        keepChromeVisible()
    }

    private func undoJump() {
        guard let position = jumpBackPosition else { return }
        jumpBackPosition = nil
        guard let index = book.spine.firstIndex(where: { spineIdentity($0) == position.spineID }) else {
            return
        }
        sectionIndex = index
        pendingAnchor = nil
        pendingPosition = position
        pendingPositionAnimated = true
        currentPosition = position
        activePanel = nil
        keepChromeVisible()
    }

    private func sectionIndex(for href: String) -> Int? {
        let rawPath = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        let path = normalizedSpinePath(rawPath)
        return book.spine.firstIndex { normalizedSpinePath($0.href) == path }
    }

    private func normalizedSpinePath(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        return decoded.hasPrefix("./") ? String(decoded.dropFirst(2)) : decoded
    }

    private struct TOCEntry: Identifiable {
        let item: EPUBTOCItem
        let depth: Int
        var id: UUID { item.id }
    }

    private func flatten(_ items: [EPUBTOCItem], depth: Int = 0) -> [TOCEntry] {
        var result: [TOCEntry] = []
        for item in items {
            result.append(TOCEntry(item: item, depth: depth))
            result.append(contentsOf: flatten(item.children, depth: depth + 1))
        }
        return result
    }

    private func panelEmpty(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(OBooksPalette.secondaryText)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(OBooksPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private func themeBackground(_ item: ReadingTheme) -> Color {
        switch item {
        case .original: return Color(red: 0.05, green: 0.05, blue: 0.05)
        case .quiet: return Color(red: 0.24, green: 0.24, blue: 0.24)
        case .paper: return Color.white
        case .bold: return Color.black
        case .calm: return Color(red: 0.25, green: 0.22, blue: 0.18)
        case .focus: return Color(red: 0.09, green: 0.09, blue: 0.07)
        }
    }

    private func themeForeground(_ item: ReadingTheme) -> Color {
        switch item {
        case .paper: return Color.black.opacity(0.85)
        case .quiet, .calm: return Color.white.opacity(0.82)
        default: return Color.white.opacity(0.88)
        }
    }
}

private struct ReaderFooter: View {
    @ObservedObject var progressState: ReaderProgressState
    let isSpeaking: Bool
    let flow: ReaderFlowMode
    let chromeBackground: Color
    let colorScheme: ColorScheme
    let chromeVisible: Bool
    let controller: ReaderController
    let onSeekStarted: () -> Void
    let onSeek: (CGFloat, CGFloat, Bool) -> Void
    @State private var isSeeking = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                controller.send(.toggleSpeech)
            } label: {
                Image(systemName: isSpeaking ? "pause.fill" : "speaker.wave.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSpeaking ? OBooksPalette.accent : .white.opacity(0.72))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(OBooksIconButtonStyle())
            .help(isSpeaking ? "停止朗读" : "朗读当前章节")

            Button {
                controller.send(.previousPage)
            } label: {
                Image(systemName: previousPageSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(OBooksIconButtonStyle())
            .help("上一页")

            progressBar

            Text(progressLabel)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, alignment: .leading)

            Button {
                controller.send(.nextPage)
            } label: {
                Image(systemName: nextPageSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(OBooksIconButtonStyle())
            .help("下一页")
        }
        .padding(.horizontal, 17)
        .frame(height: 42)
        .background(chromeBackground.opacity(colorScheme == .dark ? 0.84 : 0.94), in: Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .padding(.bottom, 10)
        .opacity(chromeVisible ? 1 : 0)
        .allowsHitTesting(chromeVisible)
        .animation(.easeOut(duration: 0.18), value: chromeVisible)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(OBooksPalette.accent)
                    .frame(
                        width: max(
                            0, geometry.size.width * CGFloat(min(max(progressState.value, 0), 1))))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.linear(duration: 0.08), value: progressState.value)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if !isSeeking {
                            isSeeking = true
                            onSeekStarted()
                        }
                        guard abs(value.location.x - value.startLocation.x) > 3 else { return }
                        seek(at: value.location.x, width: geometry.size.width, animated: false)
                    }
                    .onEnded { value in
                        if !isSeeking {
                            onSeekStarted()
                        }
                        let didDrag = abs(value.location.x - value.startLocation.x) > 3
                        seek(at: value.location.x, width: geometry.size.width, animated: !didDrag)
                        isSeeking = false
                    }
            )
            .help("跳转到阅读进度")
        }
        .frame(width: 190, height: 18)
    }

    private var progressLabel: String {
        String(format: "%d%%", Int(progressState.value * 100))
    }

    private var previousPageSymbol: String {
        flow.pageOrientation == .vertical ? "chevron.up" : "chevron.left"
    }

    private var nextPageSymbol: String {
        flow.pageOrientation == .vertical ? "chevron.down" : "chevron.right"
    }

    private func seek(at x: CGFloat, width: CGFloat, animated: Bool) {
        onSeek(x, width, animated)
    }
}

private struct ReaderPanelSurface<Content: View>: View {
    let title: String
    let width: CGFloat
    let content: Content

    init(title: String, width: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            Rectangle()
                .fill(Color.white.opacity(0.13))
                .frame(height: 1)
            content
        }
        .frame(width: width)
        .frame(minHeight: 112, maxHeight: 760)
        .background(
            Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.97),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
        .padding(.horizontal, 26)
    }
}
