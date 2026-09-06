import Combine
import Foundation
import OSLog

@MainActor
final class ReaderSearchSession: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [ReaderSearchHit] = []
    @Published private(set) var recentQueries: [String] = []
    @Published private(set) var isSearching = false
    @Published private(set) var didTruncate = false
    @Published var selectedHitID: String?

    private var book: BookSummary?
    private var tocIndex = ReaderTOCIndex(spine: [], items: [])
    private var chapterTexts: [Int: String] = [:]
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var revealFirstWhenReady = false
    private var lastCompletedQuery = ""
    private let logger = Logger(subsystem: "com.obooks.app", category: "reader.search")

    func prepare(book: BookSummary, tocIndex: ReaderTOCIndex) {
        self.tocIndex = tocIndex
        guard self.book?.id != book.id else {
            self.book = book
            return
        }
        searchTask?.cancel()
        self.book = book
        chapterTexts.removeAll()
        results = []
        query = ""
        selectedHitID = nil
        isSearching = false
        didTruncate = false
        lastCompletedQuery = ""
        revealFirstWhenReady = false
        loadRecent()
        logger.info("准备书籍搜索: chapters=\(book.spine.count)")
    }

    func updateQuery(_ value: String) {
        query = value
        revealFirstWhenReady = false
        startSearch(immediate: false)
    }

    func submit() -> ReaderSearchHit? {
        rememberCurrentQuery()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isSearching {
            revealFirstWhenReady = true
            return nil
        }
        if lastCompletedQuery.caseInsensitiveCompare(trimmed) == .orderedSame {
            return results.isEmpty ? nil : selectNext()
        }
        revealFirstWhenReady = true
        startSearch(immediate: true)
        return nil
    }

    func applyRecent(_ value: String) {
        query = value
        rememberCurrentQuery()
        revealFirstWhenReady = true
        startSearch(immediate: true)
    }

    func consumePendingReveal() -> ReaderSearchHit? {
        guard revealFirstWhenReady, !isSearching, let first = results.first else { return nil }
        revealFirstWhenReady = false
        select(first)
        return first
    }

    func clearQuery() {
        updateQuery("")
    }

    func clearRecent() {
        recentQueries = []
        persistRecent()
    }

    func select(_ hit: ReaderSearchHit) {
        selectedHitID = hit.id
        rememberCurrentQuery()
    }

    func selectNext() -> ReaderSearchHit? {
        guard !results.isEmpty else { return nil }
        if let selectedHitID, let index = results.firstIndex(where: { $0.id == selectedHitID }) {
            let next = results[(index + 1) % results.count]
            self.selectedHitID = next.id
            return next
        }
        selectedHitID = results[0].id
        return results[0]
    }

    func selectPrevious() -> ReaderSearchHit? {
        guard !results.isEmpty else { return nil }
        if let selectedHitID, let index = results.firstIndex(where: { $0.id == selectedHitID }) {
            let previous = results[(index - 1 + results.count) % results.count]
            self.selectedHitID = previous.id
            return previous
        }
        selectedHitID = results[0].id
        return results[0]
    }

    private func startSearch(immediate: Bool) {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedHitID = nil
        guard !trimmed.isEmpty, let book else {
            results = []
            isSearching = false
            didTruncate = false
            lastCompletedQuery = ""
            return
        }
        isSearching = true
        didTruncate = false
        searchTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await self?.performSearch(book: book, query: trimmed, generation: generation)
        }
    }

    private func performSearch(book: BookSummary, query: String, generation: Int) async {
        let started = Date()
        logger.info("开始搜索: chapters=\(book.spine.count), queryLength=\(query.count)")
        var collected: [ReaderSearchHit] = []
        var scanned = 0
        var truncated = false
        for index in book.spine.indices {
            guard !Task.isCancelled, generation == searchGeneration else { return }
            if chapterTexts[index] == nil {
                let extracted = await Task.detached(priority: .userInitiated) {
                    Result { try ReaderSearchTextExtractor().extract(book: book, sectionIndex: index) }
                }.value
                switch extracted {
                case .success(let text):
                    chapterTexts[index] = text
                case .failure(let error):
                    logger.error(
                        "提取章节文本失败: section=\(index), error=\(error.localizedDescription, privacy: .public)"
                    )
                    chapterTexts[index] = ""
                }
            }
            let text = chapterTexts[index] ?? ""
            let title = ReaderSearchIndex.chapterTitle(book: book, tocIndex: tocIndex, sectionIndex: index)
            let identity = book.spine[index].id.isEmpty ? book.spine[index].href : book.spine[index].id
            let chapterHits = ReaderSearchIndex.hits(
                in: text,
                query: query,
                sectionIndex: index,
                spineID: identity,
                title: title
            )
            scanned += 1
            collected.append(contentsOf: chapterHits)
            if collected.count > ReaderSearchIndex.maxHits {
                collected = Array(collected.prefix(ReaderSearchIndex.maxHits))
                truncated = true
            }
            if scanned == 1 || scanned % 8 == 0 || index == book.spine.count - 1 || truncated {
                results = collected
                if scanned % 8 == 0 {
                    logger.debug(
                        "搜索进度: chapters=\(scanned)/\(book.spine.count), hits=\(collected.count)"
                    )
                }
            }
            if truncated {
                break
            }
        }
        guard !Task.isCancelled, generation == searchGeneration else { return }
        results = collected
        didTruncate = truncated
        lastCompletedQuery = query
        isSearching = false
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        logger.info(
            "搜索完成: hits=\(collected.count), chapters=\(scanned)/\(book.spine.count), truncated=\(truncated), durationMs=\(elapsedMs)"
        )
    }

    private func rememberCurrentQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentQueries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentQueries.insert(trimmed, at: 0)
        if recentQueries.count > 8 {
            recentQueries = Array(recentQueries.prefix(8))
        }
        persistRecent()
    }

    private func loadRecent() {
        guard let book else {
            recentQueries = []
            return
        }
        recentQueries = UserDefaults.standard.stringArray(forKey: recentKey(for: book.id)) ?? []
    }

    private func persistRecent() {
        guard let book else { return }
        UserDefaults.standard.set(recentQueries, forKey: recentKey(for: book.id))
    }

    private func recentKey(for id: UUID) -> String {
        "reader.search.recent.\(id.uuidString)"
    }
}
