import Foundation
import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let book: BookSummary
    @StateObject private var controller = ReaderController()
    @State private var sectionIndex = 0
    @State private var progress = 0.0
    @State private var flow: ReadingFlow = .paginated
    @State private var theme: ReadingTheme = .paper
    @State private var fontSize = 18.0
    @State private var lineHeight = 1.7
    @State private var margin = 56.0
    @State private var showTOC = false
    @State private var showSettings = false
    @State private var isSpeaking = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .underPageBackgroundColor).ignoresSafeArea()

            ReaderWebView(
                book: book,
                sectionIndex: $sectionIndex,
                flow: flow,
                theme: theme,
                fontSize: fontSize,
                lineHeight: lineHeight,
                margin: margin,
                controller: controller,
                onProgress: { value in
                    progress = value
                    let count = Double(max(book.spine.count, 1))
                    let overall = min(1, Double(sectionIndex) / count + value / count)
                    appModel.updateProgress(bookID: book.id, fraction: overall)
                },
                onBoundary: moveSection,
                onSpeakingChanged: { value in
                    isSpeaking = value
                }
            )
            .padding(.top, 54)
            .padding(.bottom, 54)

            readerToolbar

            if showTOC {
                tocPanel.transition(.move(edge: .leading).combined(with: .opacity))
            }

            readerFooter
        }
        .frame(minWidth: 900, minHeight: 650)
        .background(.black)
        .onAppear {
            sectionIndex = initialSectionIndex
            progress = book.progressFraction
        }
        .onDisappear {
            controller.send(.stopSpeech)
        }
        .onExitCommand { dismiss() }
    }

    private var readerToolbar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .help("关闭阅读器")
                .buttonStyle(.borderless)

            Button {
                withAnimation(.easeOut(duration: 0.18)) { showTOC.toggle() }
            } label: { Image(systemName: "sidebar.left") }
                .help("显示目录")
                .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.headline).lineLimit(1)
                if book.spine.indices.contains(sectionIndex) {
                    Text(book.spine[sectionIndex].title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            Menu {
                Picker("阅读方式", selection: $flow) {
                    ForEach(ReadingFlow.allCases) { item in Text(item.label).tag(item) }
                }
            } label: {
                Image(systemName: flow == .paginated ? "rectangle.split.2x1" : "arrow.up.and.down.text.horizontal")
            }
            .help("切换阅读方式")
            .menuStyle(.borderlessButton)

            Menu {
                Picker("主题", selection: $theme) {
                    ForEach(ReadingTheme.allCases) { item in Text(item.label).tag(item) }
                }
            } label: {
                Image(systemName: theme == .dark ? "moon" : "sun.max")
            }
            .help("切换主题")
            .menuStyle(.borderlessButton)

            Button { controller.send(.toggleSpeech) } label: {
                Image(systemName: isSpeaking ? "pause.fill" : "speaker.wave.2")
            }
            .help(isSpeaking ? "停止朗读" : "朗读当前章节")
            .buttonStyle(.borderless)

            Button { showSettings.toggle() } label: { Image(systemName: "textformat.size") }
                .help("阅读设置")
                .buttonStyle(.borderless)
                .popover(isPresented: $showSettings, arrowEdge: .top) { settingsPanel }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(.regularMaterial)
    }

    private var readerFooter: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 18) {
                Button { controller.send(.previousPage) } label: { Image(systemName: "chevron.left") }
                    .help("上一页")
                    .buttonStyle(.borderless)
                ProgressView(value: progress).frame(maxWidth: 380)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
                Button { controller.send(.nextPage) } label: { Image(systemName: "chevron.right") }
                    .help("下一页")
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 22)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .frame(maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private var tocPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("目录").font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showTOC = false }
                } label: { Image(systemName: "xmark") }
                    .help("关闭目录")
                    .buttonStyle(.borderless)
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(flatten(book.toc)) { entry in
                        Button {
                            if let index = sectionIndex(for: entry.item.href) {
                                sectionIndex = index
                                showTOC = false
                            }
                        } label: {
                            Text(entry.item.label)
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, CGFloat(16 + entry.depth * 12))
                                .padding(.trailing, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 290)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .shadow(color: .black.opacity(0.18), radius: 16, x: 4)
        .padding(.top, 54)
        .padding(.bottom, 54)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("阅读设置").font(.headline)
            settingSlider(title: "字号", value: $fontSize, range: 12...32, step: 1, display: String(Int(fontSize)))
            settingSlider(title: "行距", value: $lineHeight, range: 1.2...2.4, step: 0.1, display: String(format: "%.1f", lineHeight))
            settingSlider(title: "边距", value: $margin, range: 24...100, step: 4, display: String(Int(margin)))
        }
        .padding(20)
        .frame(width: 240)
    }

    private func settingSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var initialSectionIndex: Int {
        guard !book.spine.isEmpty else { return 0 }
        return min(book.spine.count - 1, Int(book.progressFraction * Double(book.spine.count)))
    }

    private func moveSection(_ direction: Int) {
        let next = sectionIndex + (direction > 0 ? 1 : -1)
        guard book.spine.indices.contains(next) else { return }
        sectionIndex = next
    }

    private func sectionIndex(for href: String) -> Int? {
        let path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        return book.spine.firstIndex { $0.href == path }
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
}
