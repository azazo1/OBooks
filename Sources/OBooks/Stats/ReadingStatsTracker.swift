import Foundation
import OSLog

@MainActor
final class ReadingStatsTracker {
    private let ledger: ReadingStatsLedger
    private let persist: () -> Void
    private let now: () -> Date
    private let calendar: Calendar
    private let idleTimeout: TimeInterval
    private let flushInterval: TimeInterval
    private let logger = Logger(subsystem: "com.obooks.app", category: "reading.stats")

    private var activeBookID: UUID?
    private var sessionStartedAt: Date?
    private var lastInteractionAt: Date?
    private var flushTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    var isCounting: Bool { sessionStartedAt != nil }

    init(
        ledger: ReadingStatsLedger,
        persist: @escaping () -> Void,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        idleTimeout: TimeInterval = 5 * 60,
        flushInterval: TimeInterval = 15
    ) {
        self.ledger = ledger
        self.persist = persist
        self.now = now
        self.calendar = calendar
        self.idleTimeout = idleTimeout
        self.flushInterval = flushInterval
    }

    func setActive(bookID: UUID, isActive: Bool) {
        if isActive {
            if activeBookID != bookID {
                commitAndStopCounting()
                activeBookID = bookID
                logger.info("开始统计阅读时长: book=\(bookID)")
            }
            noteInteraction()
            return
        }

        guard activeBookID == bookID else { return }
        commitAndStopCounting()
        activeBookID = nil
        lastInteractionAt = nil
        logger.info("暂停统计阅读时长: book=\(bookID)")
    }

    func stop(bookID: UUID) {
        guard activeBookID == bookID else { return }
        commitAndStopCounting()
        activeBookID = nil
        lastInteractionAt = nil
        logger.info("停止统计阅读时长: book=\(bookID)")
    }

    func noteInteraction() {
        guard activeBookID != nil else { return }
        lastInteractionAt = now()
        resumeIfNeeded()
        scheduleIdle()
    }

    func flush() {
        guard let bookID = activeBookID, let started = sessionStartedAt else { return }
        let current = now()
        let duration = current.timeIntervalSince(started)
        sessionStartedAt = current
        guard duration >= 1 else { return }
        ledger.record(bookID: bookID, from: started, duration: duration, calendar: calendar)
        persist()
        logger.debug("写入阅读时长: book=\(bookID), seconds=\(duration)")
    }

    func checkIdle() {
        guard sessionStartedAt != nil else { return }
        let last = lastInteractionAt ?? sessionStartedAt ?? now()
        guard now().timeIntervalSince(last) >= idleTimeout else { return }
        logger.info("阅读空闲超时, 暂停统计")
        commitAndStopCounting()
    }

    private func resumeIfNeeded() {
        guard activeBookID != nil else { return }
        if sessionStartedAt == nil {
            sessionStartedAt = now()
        }
        scheduleFlush()
        scheduleIdle()
    }

    private func commitAndStopCounting() {
        flush()
        sessionStartedAt = nil
        flushTask?.cancel()
        flushTask = nil
        idleTask?.cancel()
        idleTask = nil
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                try? await Task.sleep(for: .seconds(self.flushInterval))
                guard !Task.isCancelled else { return }
                self.flush()
            }
        }
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        let timeout = idleTimeout
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.checkIdle()
        }
    }
}
