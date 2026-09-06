import AppKit
import SwiftUI

private struct SentenceFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct SpeechSentenceList: View {
    @ObservedObject var session: SpeechSession
    let flow: ReaderFlowMode
    let onPlay: (Int) -> Void
    @State private var candidate: Int?
    @State private var browsing = false
    @State private var clickedCandidate = false
    @State private var frames: [Int: CGRect] = [:]
    @State private var returnTask: Task<Void, Never>?
    @State private var pageTask: Task<Void, Never>?
    @State private var candidatePage: Int?
    @State private var windowStart = 0
    @State private var windowEnd = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 10) {
                        Color.clear.frame(height: geometry.size.height / 2 - 20)
                        ForEach(renderedSentences) { sentence in
                            SpeechSentenceRow(
                                sentence: sentence,
                                isCurrent: sentence.id == session.sentenceIndex,
                                isCandidate: sentence.id == candidate,
                                candidateLabel: candidateLabel(sentence.id),
                                reportsFrame: browsing
                            ) {
                                candidate = sentence.id
                                clickedCandidate = true
                                browsing = true
                                ensureWindow(around: sentence.id)
                                armReturn()
                                withAnimation(animation) { proxy.scrollTo(sentence.id, anchor: .center) }
                            } onPlay: {
                                returnTask?.cancel()
                                browsing = false
                                candidate = nil
                                onPlay(sentence.id)
                            }
                        }
                        Color.clear.frame(height: geometry.size.height / 2 - 20)
                    }
                    .padding(.horizontal, 48)
                }
                .coordinateSpace(name: "speechSentences")
                .background(SpeechListInteractionMonitor {
                    browsing = true
                    clickedCandidate = false
                    chooseCenter(height: geometry.size.height)
                    armReturn()
                })
                .onPreferenceChange(SentenceFrames.self) { next in
                    if next != frames { frames = next }
                    if browsing, !clickedCandidate { chooseCenter(height: geometry.size.height) }
                }
                .onChange(of: session.sentenceIndex) { _, index in
                    if !browsing { ensureWindow(around: index) }
                    guard !browsing else { return }
                    follow(index, proxy: proxy, height: geometry.size.height)
                }
                .onChange(of: browsing) { _, value in
                    if !value {
                        ensureWindow(around: session.sentenceIndex, resetting: true)
                        follow(session.sentenceIndex, proxy: proxy, height: geometry.size.height)
                    }
                }
                .onChange(of: session.sentences.count) { _, _ in
                    ensureWindow(around: candidate ?? session.sentenceIndex, resetting: true)
                }
                .onAppear {
                    ensureWindow(around: session.sentenceIndex, resetting: true)
                    proxy.scrollTo(session.sentenceIndex, anchor: .center)
                }
                .onChange(of: candidate) { _, index in
                    candidatePage = nil
                    pageTask?.cancel()
                    guard flow.isPaging, let index else { return }
                    pageTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { return }
                        candidatePage = session.pageForSentence?(index)
                    }
                }
            }
        }
        .onDisappear { returnTask?.cancel(); pageTask?.cancel() }
    }

    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.24) }

    private var renderedSentences: ArraySlice<SpeechSentence> {
        let sentences = session.sentences
        let count = sentences.count
        guard count > 0 else { return sentences[...] }
        if windowEnd > windowStart {
            let start = min(max(0, windowStart), count)
            let end = min(max(start, windowEnd), count)
            return sentences[start..<end]
        }
        let range = defaultWindow(around: candidate ?? session.sentenceIndex, count: count)
        return sentences[range]
    }

    private func candidateLabel(_ index: Int) -> String {
        if let candidatePage { return "第 \(candidatePage) 页" }
        return "第 \(index + 1) 句"
    }

    private func chooseCenter(height: CGFloat) {
        if let nearest = frames.min(by: { abs($0.value.midY - height / 2) < abs($1.value.midY - height / 2) }) {
            candidate = nearest.key
            ensureWindow(around: nearest.key)
        }
    }

    private func armReturn() {
        returnTask?.cancel()
        returnTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            browsing = false
            candidate = nil
        }
    }

    private func follow(_ index: Int, proxy: ScrollViewProxy, height: CGFloat) {
        let anchor: UnitPoint = (frames[index]?.height ?? 0) > height ? .top : .center
        withAnimation(animation) { proxy.scrollTo(index, anchor: anchor) }
    }

    private func defaultWindow(around focus: Int, count: Int) -> Range<Int> {
        let radius = 40
        let start = max(0, focus - radius)
        let end = min(count, focus + radius + 1)
        return start..<end
    }

    private func ensureWindow(around focus: Int, resetting: Bool = false) {
        let count = session.sentences.count
        guard count > 0 else {
            windowStart = 0
            windowEnd = 0
            return
        }
        let desired = defaultWindow(around: focus, count: count)
        if resetting || windowEnd <= windowStart {
            windowStart = desired.lowerBound
            windowEnd = desired.upperBound
            return
        }
        if browsing {
            windowStart = min(windowStart, desired.lowerBound)
            windowEnd = max(windowEnd, desired.upperBound)
            return
        }
        let margin = 12
        if focus < windowStart + margin || focus >= windowEnd - margin {
            windowStart = desired.lowerBound
            windowEnd = desired.upperBound
        }
    }
}

private struct SpeechSentenceRow: View {
    let sentence: SpeechSentence
    let isCurrent: Bool
    let isCandidate: Bool
    let candidateLabel: String
    let reportsFrame: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(sentence.text)
                .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundStyle(.primary.opacity(isCurrent ? 1 : isCandidate ? 0.8 : 0.45))
                .padding(.vertical, 10)
                .padding(.leading, 5)
                .padding(.trailing, isCandidate ? 88 : 5)
                .frame(maxWidth: .infinity)
                .background(.primary.opacity(isCurrent ? 0.06 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sentence.text)
        .accessibilityValue(isCurrent ? "正在朗读" : "")
        .overlay(alignment: .trailing) {
            if isCandidate {
                HStack(spacing: 8) {
                    Text(candidateLabel)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button(action: onPlay) {
                        Image(systemName: "play.fill").font(.system(size: 12))
                            .frame(width: 30, height: 30)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("从这一句开始朗读")
                    .accessibilityLabel("从第 \(sentence.id + 1) 句开始朗读")
                }
                .padding(.trailing, 8)
            }
        }
        .background {
            if reportsFrame {
                GeometryReader { row in
                    Color.clear.preference(key: SentenceFrames.self,
                        value: [sentence.id: row.frame(in: .named("speechSentences"))])
                }
            }
        }
        .id(sentence.id)
    }
}

private struct SpeechListInteractionMonitor: NSViewRepresentable {
    let onInteraction: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.onInteraction = onInteraction }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.removeMonitor() }

    final class MonitorView: NSView {
        var onInteraction: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDragged]) { [weak self] event in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.onInteraction?()
                return event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
