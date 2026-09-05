import Foundation
import XCTest
@testable import OBooks

final class ReadingStatsTests: XCTestCase {
    func testRecordSplitsAcrossHourBoundary() {
        let calendar = makeCalendar()
        let ledger = ReadingStatsLedger()
        let bookID = UUID()
        let start = date(2026, 9, 5, 10, 50, calendar: calendar)

        ledger.record(bookID: bookID, from: start, duration: 20 * 60, calendar: calendar)

        XCTAssertEqual(seconds(in: ledger, bookID: bookID, day: ReadingDay(year: 2026, month: 9, day: 5), hour: 10), 600)
        XCTAssertEqual(seconds(in: ledger, bookID: bookID, day: ReadingDay(year: 2026, month: 9, day: 5), hour: 11), 600)
    }

    func testRecordSplitsAcrossMidnight() {
        let calendar = makeCalendar()
        let ledger = ReadingStatsLedger()
        let bookID = UUID()
        let start = date(2026, 9, 5, 23, 50, calendar: calendar)

        ledger.record(bookID: bookID, from: start, duration: 20 * 60, calendar: calendar)

        XCTAssertEqual(seconds(in: ledger, bookID: bookID, day: ReadingDay(year: 2026, month: 9, day: 5), hour: 23), 600)
        XCTAssertEqual(seconds(in: ledger, bookID: bookID, day: ReadingDay(year: 2026, month: 9, day: 6), hour: 0), 600)
    }

    func testRecordAccumulatesTheSameHourBucket() {
        let calendar = makeCalendar()
        let ledger = ReadingStatsLedger()
        let bookID = UUID()
        let start = date(2026, 9, 5, 8, 10, calendar: calendar)

        ledger.record(bookID: bookID, from: start, duration: 120, calendar: calendar)
        ledger.record(bookID: bookID, from: start, duration: 80, calendar: calendar)

        XCTAssertEqual(seconds(in: ledger, bookID: bookID, day: ReadingDay(year: 2026, month: 9, day: 5), hour: 8), 200)
        XCTAssertEqual(ledger.buckets.count, 1)
    }

    func testTodayHoursAlwaysReturnsTwentyFourSlots() {
        let calendar = makeCalendar()
        let ledger = ReadingStatsLedger()
        let bookID = UUID()
        let now = date(2026, 9, 5, 21, 0, calendar: calendar)
        ledger.record(bookID: bookID, from: now, duration: 90, calendar: calendar)

        let points = ledger.todayHours(bookID: bookID, now: now, calendar: calendar)

        XCTAssertEqual(points.map(\.hour), Array(0..<24))
        XCTAssertEqual(points[21].seconds, 90)
        XCTAssertEqual(points.filter { $0.hour != 21 }.map(\.seconds).allSatisfy { $0 == 0 }, true)
    }

    func testRecentDaysIncludeEmptyDaysAndOnlyMatchingBooks() {
        let calendar = makeCalendar()
        let ledger = ReadingStatsLedger()
        let first = UUID()
        let second = UUID()
        let now = date(2026, 9, 5, 12, 0, calendar: calendar)
        ledger.record(bookID: first, from: date(2026, 9, 3, 9, 0, calendar: calendar), duration: 300, calendar: calendar)
        ledger.record(bookID: second, from: date(2026, 9, 5, 9, 0, calendar: calendar), duration: 120, calendar: calendar)

        let all = ledger.recentDays(count: 4, now: now, calendar: calendar)
        let onlyFirst = ledger.recentDays(count: 4, now: now, calendar: calendar, bookID: first)

        XCTAssertEqual(all.map(\.day), [
            ReadingDay(year: 2026, month: 9, day: 2),
            ReadingDay(year: 2026, month: 9, day: 3),
            ReadingDay(year: 2026, month: 9, day: 4),
            ReadingDay(year: 2026, month: 9, day: 5),
        ])
        XCTAssertEqual(all.map(\.seconds), [0, 300, 0, 120])
        XCTAssertEqual(onlyFirst.map(\.seconds), [0, 300, 0, 0])
    }

    func testCheckInRequiresFiveMinutesAndIgnoresOtherMonths() {
        let calendar = makeCalendar()
        let ledger = ReadingStatsLedger()
        let bookID = UUID()
        ledger.record(bookID: bookID, from: date(2026, 8, 31, 10, 0, calendar: calendar), duration: 5 * 60, calendar: calendar)
        ledger.record(bookID: bookID, from: date(2026, 9, 1, 10, 0, calendar: calendar), duration: 5 * 60 - 1, calendar: calendar)
        ledger.record(bookID: bookID, from: date(2026, 9, 5, 10, 0, calendar: calendar), duration: 5 * 60, calendar: calendar)
        ledger.record(bookID: bookID, from: date(2026, 9, 6, 10, 0, calendar: calendar), duration: 12 * 60, calendar: calendar)

        let month = date(2026, 9, 20, 0, 0, calendar: calendar)
        XCTAssertFalse(ReadingCheckIn.qualifies(5 * 60 - 1))
        XCTAssertTrue(ReadingCheckIn.qualifies(5 * 60))
        XCTAssertEqual(ledger.checkInCount(inMonthOf: month, calendar: calendar), 2)
        XCTAssertEqual(ledger.secondsByDay(inMonthOf: month, calendar: calendar).count, 3)
    }

    func testRemoveBookDropsOnlyThatBook() {
        let calendar = makeCalendar()
        let ledger = ReadingStatsLedger()
        let kept = UUID()
        let removed = UUID()
        ledger.record(bookID: kept, from: date(2026, 9, 5, 10, 0, calendar: calendar), duration: 60, calendar: calendar)
        ledger.record(bookID: removed, from: date(2026, 9, 5, 11, 0, calendar: calendar), duration: 90, calendar: calendar)

        ledger.removeBook(removed)

        XCTAssertEqual(ledger.buckets.map(\.bookID), [kept])
        XCTAssertEqual(ledger.totalSeconds(on: ReadingDay(year: 2026, month: 9, day: 5)), 60)
    }

    func testStoreRoundTripsBucketsAndRejectsUnknownSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadingStatsStore(rootURL: directory)
        let buckets = [
            ReadingTimeBucket(
                bookID: UUID(),
                day: ReadingDay(year: 2026, month: 9, day: 5),
                hour: 21,
                seconds: 125
            )
        ]

        store.save(buckets)
        XCTAssertEqual(store.load(), buckets)

        let payload: [String: Any] = ["schemaVersion": 2, "buckets": []]
        try JSONSerialization.data(withJSONObject: payload).write(
            to: directory.appendingPathComponent("reading-stats.json")
        )
        XCTAssertEqual(store.load(), [])
    }

    @MainActor
    func testTrackerFlushesActiveTimeAndIgnoresIdleTail() {
        let calendar = makeCalendar()
        var current = date(2026, 9, 5, 10, 0, calendar: calendar)
        let ledger = ReadingStatsLedger()
        var saved = 0
        let bookID = UUID()
        let tracker = ReadingStatsTracker(
            ledger: ledger,
            persist: { saved += 1 },
            now: { current },
            calendar: calendar,
            idleTimeout: 300,
            flushInterval: 15
        )

        tracker.setActive(bookID: bookID, isActive: true)
        current.addTimeInterval(120)
        tracker.flush()
        XCTAssertEqual(ledger.totalSeconds(on: ReadingDay(year: 2026, month: 9, day: 5), bookID: bookID), 120)
        XCTAssertEqual(saved, 1)
        XCTAssertTrue(tracker.isCounting)

        current.addTimeInterval(301)
        tracker.checkIdle()
        XCTAssertFalse(tracker.isCounting)
        XCTAssertEqual(ledger.totalSeconds(on: ReadingDay(year: 2026, month: 9, day: 5), bookID: bookID), 421)

        current.addTimeInterval(60)
        tracker.flush()
        XCTAssertEqual(ledger.totalSeconds(on: ReadingDay(year: 2026, month: 9, day: 5), bookID: bookID), 421)

        tracker.noteInteraction()
        current.addTimeInterval(30)
        tracker.flush()
        XCTAssertEqual(ledger.totalSeconds(on: ReadingDay(year: 2026, month: 9, day: 5), bookID: bookID), 451)

        tracker.setActive(bookID: bookID, isActive: false)
        current.addTimeInterval(90)
        tracker.flush()
        XCTAssertEqual(ledger.totalSeconds(on: ReadingDay(year: 2026, month: 9, day: 5), bookID: bookID), 451)
        XCTAssertFalse(tracker.isCounting)
    }

    private func seconds(
        in ledger: ReadingStatsLedger,
        bookID: UUID,
        day: ReadingDay,
        hour: Int
    ) -> TimeInterval {
        ledger.buckets.first { $0.bookID == bookID && $0.day == day && $0.hour == hour }?.seconds ?? 0
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: 0)
        )!
    }
}
