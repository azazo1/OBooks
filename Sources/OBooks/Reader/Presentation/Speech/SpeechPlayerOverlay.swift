import AppKit
import SwiftUI

struct SpeechPlayerOverlay: View {
    @ObservedObject var session: SpeechSession
    let controller: ReaderController
    let book: BookSummary
    let theme: ReadingTheme
    let flow: ReaderFlowMode
    let onFrameChange: (CGRect) -> Void
    @EnvironmentObject private var appModel: AppModel
    @State private var offset = CGSize.zero
    @GestureState private var translation = CGSize.zero
    @State private var draftRate = 1.0
    @State private var voices: [SpeechVoice] = []
    private static let sleepPresets: [(seconds: TimeInterval, label: String)] = [
        (60, "1 分钟"),
        (300, "5 分钟"),
        (600, "10 分钟"),
        (900, "15 分钟"),
        (1200, "20 分钟"),
        (1800, "30 分钟"),
        (2700, "45 分钟"),
        (3600, "1 小时"),
        (7200, "2 小时"),
    ]

    var body: some View {
        GeometryReader { geometry in
            if session.isPlayerVisible {
                let size = CGSize(width: min(420, geometry.size.width - 32),
                    height: session.isExpanded ? min(510, geometry.size.height * 0.8) : 84)
                let origin = playerOrigin(container: geometry.size, size: size)
                VStack(spacing: 0) {
                    dragHandle(container: geometry.size, size: size)
                    if session.isExpanded { expandedPlayer } else { miniPlayer }
                }
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: NativeReaderAppearance(theme: theme).background).opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    SystemCursorBarrier()
                        .allowsHitTesting(false)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .foregroundStyle(Color(nsColor: NativeReaderAppearance(theme: theme).foreground))
                .preferredColorScheme(theme == .bold || theme == .focus ? .dark : .light)
                .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                .onChange(of: CGRect(origin: origin, size: size), initial: true) { _, frame in
                    guard translation == .zero else { return }
                    onFrameChange(frame)
                }
                .onChange(of: translation) { _, value in
                    if value == .zero { onFrameChange(CGRect(origin: origin, size: size)) }
                }
            }
        }
        .coordinateSpace(name: "speechPlayerWindow")
        .onChange(of: session.isPlayerVisible) { _, visible in
            if !visible { onFrameChange(.zero) }
        }
        .onChange(of: session.rate, initial: true) { _, rate in draftRate = rate }
        .onChange(of: session.isExpanded) { _, expanded in
            if expanded { voices = SpeechVoiceCatalog.installed() }
        }
        .onAppear { voices = SpeechVoiceCatalog.installed() }
    }

    private var miniPlayer: some View {
        HStack(spacing: 8) {
            Button { session.isExpanded = true } label: {
                HStack(spacing: 9) {
                    cover
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        statusView(fontSize: 11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .help("展开朗读播放器")
            HStack(spacing: 5) {
                control("backward.end.fill", "上一句") { controller.send(.speechStep(-1, paragraph: false)) }
                    .disabled(session.sentences.isEmpty)
                playButton(size: 34)
                control("forward.end.fill", "下一句") { controller.send(.speechStep(1, paragraph: false)) }
                    .disabled(session.sentences.isEmpty)
                sleepMenu(compact: true)
                control("minus", "最小化朗读播放器") { session.minimizePlayer() }
                control("stop.fill", "停止朗读") { controller.send(.stopSpeech) }
            }
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private var expandedPlayer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                cover
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    statusView(fontSize: 12)
                }
                Spacer(minLength: 0)
                control("chevron.down", "收起播放器") { session.isExpanded = false }
                control("minus", "最小化朗读播放器") { session.minimizePlayer() }
                control("stop.fill", "停止朗读") { controller.send(.stopSpeech) }
            }

            if session.state == .failed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 24))
                    Text(session.errorMessage ?? "无法加载朗读章节")
                        .font(.system(size: 12)).lineLimit(3).multilineTextAlignment(.center)
                    Button("重试", systemImage: "arrow.clockwise") { controller.send(.toggleSpeech) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.sentences.isEmpty {
                Group {
                    if session.state == .ended { Image(systemName: "checkmark.circle") }
                    else { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SpeechSentenceList(session: session, flow: flow) { controller.send(.speechSentence($0)) }
                    .id(session.sectionIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }

            HStack {
                Text("第 \(session.sentences.isEmpty ? 0 : session.sentenceIndex + 1) / \(session.sentences.count) 句")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                control("scope", "返回朗读位置") { controller.send(.revealSpeech) }
                    .disabled(session.position == nil)
            }
            HStack(spacing: 14) {
                control("backward.fill", "上一段") { controller.send(.speechStep(-1, paragraph: true)) }
                control("backward.end.fill", "上一句") { controller.send(.speechStep(-1, paragraph: false)) }
                playButton(size: 44)
                control("forward.end.fill", "下一句") { controller.send(.speechStep(1, paragraph: false)) }
                control("forward.fill", "下一段") { controller.send(.speechStep(1, paragraph: true)) }
            }
            .disabled(session.sentences.isEmpty && session.state != .failed)
            Divider()
            HStack(spacing: 8) {
                voiceMenu
                sleepMenu(compact: false)
                    .frame(width: 118, alignment: .leading)
            }
            HStack(spacing: 10) {
                Image(systemName: "speedometer").frame(width: 20)
                Slider(value: $draftRate, in: 0.5...2, step: 0.05) { editing in
                    if !editing { controller.send(.speechRate(draftRate)) }
                }
                .accessibilityLabel("朗读语速")
                Text(String(format: "%.2fx", draftRate))
                    .font(.system(size: 12).monospacedDigit()).frame(width: 48, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var voiceMenu: some View {
        Menu {
            ForEach(Array(Set(voices.map(\.language))).sorted(), id: \.self) { language in
                Section(Locale.current.localizedString(forLanguageCode: language) ?? language) {
                    ForEach(voices.filter { $0.language == language }) { voice in
                        Button {
                            controller.send(.speechVoice(voice.id))
                        } label: {
                            if voice.id == session.voiceIdentifier { Label(voice.label, systemImage: "checkmark") }
                            else { Text(voice.label) }
                        }
                    }
                }
            }
        } label: {
            Label(voices.first(where: { $0.id == session.voiceIdentifier })?.label ?? "系统音色", systemImage: "waveform")
                .font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .help("选择朗读音色")
        .accessibilityLabel("朗读音色")
    }

    private func sleepMenu(compact: Bool) -> some View {
        Menu {
            sleepItem("关闭", selected: session.sleepOption == .off) {
                session.setSleepOption(.off)
            }
            sleepItem("本章结束", selected: session.sleepOption == .endOfChapter) {
                session.setSleepOption(.endOfChapter)
            }
            Divider()
            ForEach(Self.sleepPresets, id: \.seconds) { preset in
                sleepItem(preset.label, selected: session.sleepOption == .after(preset.seconds)) {
                    session.setSleepOption(.after(preset.seconds))
                }
            }
        } label: {
            if compact {
                Image(systemName: session.sleepOption == .off ? "timer" : "timer.circle.fill")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(session.sleepOption == .off ? .primary : Color.accentColor)
                    .contentShape(Rectangle())
            } else {
                Label {
                    sleepMenuTitle
                } icon: {
                    Image(systemName: "timer")
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(compact ? .hidden : .automatic)
        .fixedSize(horizontal: compact, vertical: true)
        .help("朗读定时结束")
        .accessibilityLabel("朗读定时结束")
        .accessibilityValue(session.sleepStatusText() ?? "关闭")
    }

    @ViewBuilder
    private var sleepMenuTitle: some View {
        if session.sleepDeadline != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(session.sleepStatusText(at: context.date) ?? "定时结束")
                    .monospacedDigit()
            }
        } else {
            Text(session.sleepStatusText() ?? "定时结束")
        }
    }

    private func sleepItem(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private var cover: some View {
        BookCoverImage(book: book, store: appModel.libraryStore)
            .frame(width: 34, height: 44)
            .accessibilityHidden(true)
    }

    private func statusView(fontSize: CGFloat) -> some View {
        Group {
            if session.sleepDeadline != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(statusLabel(at: context.date))
                }
            } else {
                Text(statusLabel(at: Date()))
            }
        }
        .font(.system(size: fontSize))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func statusLabel(at date: Date) -> String {
        if let timer = session.sleepStatusText(at: date), session.state != .ended, session.state != .failed {
            switch session.state {
            case .paused: return "\(timer) - 已暂停"
            default: return "\(timer) - \(session.chapterTitle)"
            }
        }
        switch session.state {
        case .ended: return "朗读完成"
        case .failed: return "朗读已中断"
        case .paused: return "已暂停 - \(session.chapterTitle)"
        default: return session.chapterTitle
        }
    }

    private func playButton(size: CGFloat) -> some View {
        Button { controller.send(.toggleSpeech) } label: {
            ZStack {
                Circle().fill(Color.accentColor)
                if session.state == .preparing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: session.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size == 44 ? 18 : 13, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .help(session.state.isPlaying ? "暂停朗读" : "继续朗读")
        .accessibilityLabel(session.state.isPlaying ? "暂停朗读" : "继续朗读")
    }

    private func control(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 28, height: 28)
        }
        .buttonStyle(OBooksIconButtonStyle(size: 28, cornerRadius: 5))
        .help(title)
        .accessibilityLabel(title)
    }

    private func playerOrigin(container: CGSize, size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(16, (container.width - size.width) / 2 + offset.width + translation.width), container.width - size.width - 16),
            y: min(max(60, container.height - size.height - 76 + offset.height + translation.height), container.height - size.height - 64)
        )
    }

    private func dragHandle(container: CGSize, size: CGSize) -> some View {
        Capsule().fill(.secondary.opacity(0.35)).frame(width: 34, height: 3)
            .frame(maxWidth: .infinity).frame(height: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("speechPlayerWindow"))
                .updating($translation) { value, state, transaction in
                    transaction.disablesAnimations = true
                    state = value.translation
                }
                .onEnded { value in
                    let x = min(max(16, (container.width - size.width) / 2 + offset.width + value.translation.width), container.width - size.width - 16)
                    let y = min(max(60, container.height - size.height - 76 + offset.height + value.translation.height), container.height - size.height - 64)
                    offset = CGSize(width: x - (container.width - size.width) / 2, height: y - (container.height - size.height - 76))
                })
            .help("移动朗读播放器")
    }
}
