import Combine
import Foundation
import OSLog

enum SpeechPlaybackState: Equatable {
    case idle, preparing, playing, paused, ended, failed

    var isActive: Bool { self != .idle && self != .ended }
    var isPlaying: Bool { self == .playing || self == .preparing }
}

@MainActor
final class SpeechPlaybackOwner {
    private weak var active: SpeechSession?

    func activate(_ session: SpeechSession) {
        if active !== session { active?.pause() }
        active = session
    }
}

@MainActor
final class SpeechSession: ObservableObject {
    @Published private(set) var state: SpeechPlaybackState = .idle
    @Published private(set) var sentences: [SpeechSentence] = []
    @Published private(set) var sentenceIndex = 0
    @Published private(set) var sectionIndex = 0
    @Published private(set) var chapterTitle = ""
    @Published private(set) var rate: Double
    @Published private(set) var voiceIdentifier = ""
    @Published private(set) var errorMessage: String?
    @Published var isExpanded = false
    @Published private(set) var isMinimized = false
    var isPlayerVisible: Bool { state != .idle && !isMinimized }
    private(set) var position: SpeechPosition?
    var onPosition: ((SpeechPosition) -> Void)?
    var onStateChanged: ((SpeechPlaybackState) -> Void)?
    var onReveal: (() -> Void)?
    var pageForSentence: ((Int) -> Int?)?
    weak var playbackOwner: SpeechPlaybackOwner?

    private let engine: any SpeechEngine
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.obooks.app", category: "speech.session")
    private var spineIDs: [String] = []
    private var title: (Int) -> String = { "第 \($0 + 1) 章" }
    private var loadText: ((Int) throws -> String)?
    private var indexes: [Int: SpeechTextIndex] = [:]
    private var loadTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private let startupTimeout: Duration
    private var revision = 0
    private var requestID: UUID?
    private var utteranceOffset = 0
    private var canResume = false
    private var failedSection: Int?
    private var language: String?

    init(engine: (any SpeechEngine)? = nil, defaults: UserDefaults = .standard, startupTimeout: Duration = .seconds(15)) {
        self.engine = engine ?? SpeechService()
        self.defaults = defaults
        self.startupTimeout = startupTimeout
        let savedRate = defaults.double(forKey: "reader.speech.rate")
        rate = savedRate.isFinite && savedRate > 0 ? min(2, max(0.5, savedRate)) : 1
        self.engine.onEvent = { [weak self] event in self?.receive(event) }
    }

    func configure(spineIDs: [String], title: @escaping (Int) -> String, loadText: @escaping (Int) throws -> String) {
        self.spineIDs = spineIDs
        self.title = title
        self.loadText = loadText
    }

    func start(section: Int, offset: Int = 0) {
        restorePlayer()
        playbackOwner?.activate(self)
        load(section: section, offset: offset, autoplay: true)
    }

    func toggle() {
        if state.isPlaying { pause() } else { resume() }
    }

    func minimizePlayer() {
        guard state != .idle else { return }
        isMinimized = true
    }

    func restorePlayer() {
        isMinimized = false
    }

    func pause() {
        guard state.isPlaying else { return }
        revision &+= 1
        loadTask?.cancel()
        loadTask = nil
        startupTask?.cancel()
        canResume = requestID != nil && engine.pause()
        if !canResume { requestID = nil; engine.stop() }
        setState(.paused)
        logger.info("暂停朗读: chapter=\(self.sectionIndex + 1)")
    }

    func resume() {
        guard state == .paused || state == .ended || state == .failed else { return }
        playbackOwner?.activate(self)
        if state == .failed {
            load(section: failedSection ?? sectionIndex, offset: 0, autoplay: true)
        } else if state == .ended {
            load(section: sectionIndex, offset: 0, autoplay: true)
        } else if canResume, requestID != nil, engine.resume() {
            setState(.playing)
        } else if sentences.indices.contains(sentenceIndex) {
            speakSentence(at: sentenceIndex, offset: position?.range.location)
        } else {
            load(section: sectionIndex, offset: 0, autoplay: true)
        }
    }

    func stop() {
        revision &+= 1
        loadTask?.cancel()
        prefetchTask?.cancel()
        startupTask?.cancel()
        loadTask = nil
        prefetchTask = nil
        requestID = nil
        canResume = false
        engine.stop()
        position = nil
        indexes.removeAll()
        isExpanded = false
        isMinimized = false
        errorMessage = nil
        setState(.idle)
        logger.info("停止朗读")
    }

    func playSentence(_ index: Int) {
        guard sentences.indices.contains(index) else { return }
        playbackOwner?.activate(self)
        revision &+= 1
        loadTask?.cancel()
        speakSentence(at: index)
        onReveal?()
    }

    func step(_ direction: Int, byParagraph: Bool = false) {
        guard !sentences.isEmpty else { return }
        let autoplay = state != .paused
        var target = sentenceIndex + direction
        if byParagraph {
            let paragraph = sentences[sentenceIndex].paragraph
            while sentences.indices.contains(target), sentences[target].paragraph == paragraph {
                target += direction
            }
            if direction < 0, sentences.indices.contains(target) {
                let previousParagraph = sentences[target].paragraph
                while target > 0, sentences[target - 1].paragraph == previousParagraph { target -= 1 }
            }
        }
        if sentences.indices.contains(target) {
            revision &+= 1
            loadTask?.cancel()
            if autoplay {
                playbackOwner?.activate(self)
                speakSentence(at: target)
            } else {
                engine.stop()
                requestID = nil
                canResume = false
                sentenceIndex = target
                publishPosition(sentences[target].range)
            }
            onReveal?()
        } else if spineIDs.indices.contains(sectionIndex + direction) {
            if autoplay { playbackOwner?.activate(self) }
            load(section: sectionIndex + direction, offset: direction < 0 ? Int.max : 0,
                autoplay: autoplay, direction: direction)
        }
    }

    func setRate(_ value: Double) {
        guard value.isFinite else { return }
        let next = min(2, max(0.5, (value * 20).rounded() / 20))
        guard next != rate else { return }
        rate = next
        defaults.set(next, forKey: "reader.speech.rate")
        restartWithSettings()
        logger.info("调整朗读语速: rate=\(next)")
    }

    func setVoice(_ identifier: String) {
        guard identifier != voiceIdentifier else { return }
        voiceIdentifier = identifier
        defaults.set(identifier, forKey: "reader.speech.voice.\(language ?? "default")")
        restartWithSettings()
        logger.info("切换朗读音色")
    }

    private func restartWithSettings() {
        canResume = false
        requestID = nil
        engine.stop()
        startupTask?.cancel()
        if state.isPlaying, sentences.indices.contains(sentenceIndex) {
            speakSentence(at: sentenceIndex, offset: position?.range.location)
        }
    }

    private func load(section: Int, offset: Int, autoplay: Bool, direction: Int = 1) {
        revision &+= 1
        let expected = revision
        loadTask?.cancel()
        prefetchTask?.cancel()
        startupTask?.cancel()
        requestID = nil
        engine.stop()
        canResume = false
        errorMessage = nil
        failedSection = nil
        sectionIndex = section
        sentences = []
        position = nil
        setState(autoplay ? .preparing : .paused)
        loadTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            var candidate = section
            while self.spineIDs.indices.contains(candidate) {
                guard !Task.isCancelled, self.revision == expected else { return }
                do {
                    let index = try self.index(for: candidate)
                    let target = offset == Int.max ? index.sentences.indices.last : index.sentence(at: candidate == section ? offset : 0)
                    if let target {
                        self.sectionIndex = candidate
                        self.chapterTitle = self.title(candidate)
                        self.sentences = index.sentences
                        self.sentenceIndex = target
                        self.language = index.language
                        self.resolveVoice()
                        self.indexes = self.indexes.filter { $0.key == candidate || $0.key == candidate + 1 }
                        if autoplay {
                            self.speakSentence(at: target, offset: candidate == section && offset != Int.max ? offset : nil)
                        } else {
                            self.publishPosition(index.sentences[target].range)
                        }
                        self.prefetch(after: candidate)
                        self.logger.info("朗读进入章节: chapter=\(candidate + 1), sentences=\(index.sentences.count)")
                        return
                    }
                } catch {
                    self.failedSection = candidate
                    self.errorMessage = error.localizedDescription
                    self.setState(.failed)
                    self.logger.error("加载朗读章节失败: chapter=\(candidate + 1), error=\(error.localizedDescription)")
                    return
                }
                candidate += direction
                await Task.yield()
            }
            guard !Task.isCancelled, self.revision == expected else { return }
            self.setState(.ended)
        }
    }

    private func index(for section: Int) throws -> SpeechTextIndex {
        if let index = indexes[section] { return index }
        guard let loadText else { throw CocoaError(.fileReadUnknown) }
        logger.info("准备朗读文本: chapter=\(section + 1)")
        let started = ContinuousClock.now
        let index = SpeechTextIndex(text: try loadText(section))
        indexes[section] = index
        logger.debug("朗读文本就绪: chapter=\(section + 1), elapsed=\(String(describing: started.duration(to: .now)))")
        return index
    }

    private func prefetch(after section: Int) {
        guard spineIDs.indices.contains(section + 1) else { return }
        prefetchTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.sectionIndex == section else { return }
            _ = try? self.index(for: section + 1)
        }
    }

    private func resolveVoice() {
        let saved = defaults.string(forKey: "reader.speech.voice.\(language ?? "default")")
        if let saved, SpeechVoiceCatalog.installed().contains(where: { $0.id == saved }) {
            voiceIdentifier = saved
        } else {
            voiceIdentifier = SpeechVoiceCatalog.defaultIdentifier(language: language) ?? ""
        }
    }

    private func speakSentence(at index: Int, offset: Int? = nil) {
        guard sentences.indices.contains(index) else { return }
        startupTask?.cancel()
        requestID = nil
        engine.stop()
        canResume = false
        sentenceIndex = index
        let sentence = sentences[index]
        let start = min(NSMaxRange(sentence.range) - 1, max(sentence.range.location, offset ?? sentence.range.location))
        let localOffset = (sentence.text as NSString).rangeOfComposedCharacterSequence(at: start - sentence.range.location).location
        utteranceOffset = sentence.range.location + localOffset
        let id = UUID()
        requestID = id
        setState(.preparing)
        publishPosition(NSRange(location: utteranceOffset, length: 1))
        startupTask = Task { @MainActor [weak self, startupTimeout] in
            do { try await Task.sleep(for: startupTimeout) } catch { return }
            guard let self, self.requestID == id, self.state == .preparing else { return }
            self.requestID = nil
            self.engine.stop()
            self.errorMessage = "语音未能启动, 请重试或选择其他系统音色"
            self.setState(.failed)
            self.logger.error("系统语音启动超时")
        }
        engine.speak(text: (sentence.text as NSString).substring(from: localOffset),
            voiceIdentifier: voiceIdentifier.isEmpty ? nil : voiceIdentifier, rate: Float(rate), id: id)
    }

    private func receive(_ event: SpeechEngineEvent) {
        switch event {
        case .started(let id):
            guard id == requestID else { return }
            startupTask?.cancel()
            if state == .paused { canResume = engine.pause() } else { setState(.playing) }
        case .range(let id, let range):
            guard id == requestID, state.isPlaying, sentences.indices.contains(sentenceIndex) else { return }
            let valid = NSIntersectionRange(NSRange(location: utteranceOffset + range.location, length: range.length), sentences[sentenceIndex].range)
            if valid.length > 0 { publishPosition(valid) }
        case .finished(let id):
            guard id == requestID else { return }
            requestID = nil
            canResume = false
            guard state.isPlaying else { return }
            if sentenceIndex + 1 < sentences.count {
                speakSentence(at: sentenceIndex + 1)
            } else if sectionIndex + 1 < spineIDs.count {
                load(section: sectionIndex + 1, offset: 0, autoplay: true)
            } else {
                setState(.ended)
                logger.info("全书朗读完成")
            }
        case .paused(let id):
            guard id == requestID, state == .paused else { return }
            canResume = true
            setState(.paused)
        case .cancelled(let id):
            guard id == requestID else { return }
            requestID = nil
            canResume = false
            setState(.paused)
        }
    }

    private func publishPosition(_ range: NSRange) {
        guard spineIDs.indices.contains(sectionIndex) else { return }
        let next = SpeechPosition(sectionIndex: sectionIndex, spineID: spineIDs[sectionIndex], range: range)
        position = next
        onPosition?(next)
    }

    private func setState(_ next: SpeechPlaybackState) {
        guard state != next else { return }
        state = next
        onStateChanged?(next)
    }
}
