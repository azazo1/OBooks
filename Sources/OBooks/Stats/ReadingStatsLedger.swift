import Combine
import Foundation
import OSLog

final class ReadingStatsLedger: ObservableObject {
    @Published private(set) var buckets: [ReadingTimeBucket] = []
    private(set) var events: [ReadingEvent] = []

    private var index: [BucketKey: Int] = [:]
    private let logger = Logger(subsystem: "com.obooks.app", category: "reading.stats")

    private struct BucketKey: Hashable {
        var bookID: UUID
        var day: ReadingDay
        var hour: Int
    }

    init(buckets: [ReadingTimeBucket] = []) {
        events = buckets.map { ReadingEvent(id: UUID(), bookID: $0.bookID, day: $0.day, hour: $0.hour, seconds: $0.seconds) }
        rebuild(buckets)
        logger.info("载入阅读统计: buckets=\(self.buckets.count)")
    }

    func replaceAll(_ buckets: [ReadingTimeBucket]) {
        events = buckets.map { ReadingEvent(id: UUID(), bookID: $0.bookID, day: $0.day, hour: $0.hour, seconds: $0.seconds) }
        rebuild(buckets)
    }

    func replaceEvents(_ events: [ReadingEvent]) {
        var seen = Set<UUID>()
        self.events = events.filter { seen.insert($0.id).inserted }
        rebuild(self.events.map { ReadingTimeBucket(bookID: $0.bookID, day: $0.day, hour: $0.hour, seconds: $0.seconds) })
    }

    func record(bookID: UUID, from start: Date, duration: TimeInterval, calendar: Calendar) {
        guard duration >= 1 else { return }
        objectWillChange.send()
        var remaining = duration
        var cursor = start
        while remaining >= 0.5 {
            let hourEnd = Self.nextHourBoundary(after: cursor, calendar: calendar)
            let slice = min(remaining, hourEnd.timeIntervalSince(cursor))
            guard slice > 0 else { break }
            if slice >= 0.5 {
                let hour = calendar.component(.hour, from: cursor)
                add(
                    bookID: bookID,
                    day: ReadingDay(date: cursor, calendar: calendar),
                    hour: hour,
                    seconds: slice
                )
            }
            remaining -= slice
            cursor = hourEnd
        }
    }

    func removeBook(_ id: UUID) {
        events.removeAll { $0.bookID == id }
        let remaining = buckets.filter { $0.bookID != id }
        guard remaining.count != buckets.count else { return }
        rebuild(remaining)
        logger.info("移除图书阅读统计: book=\(id)")
    }

    func todayHours(bookID: UUID, now: Date, calendar: Calendar) -> [ReadingHourPoint] {
        let day = ReadingDay(date: now, calendar: calendar)
        var hours = Array(repeating: 0.0, count: 24)
        for bucket in buckets where bucket.bookID == bookID && bucket.day == day {
            guard (0..<24).contains(bucket.hour) else { continue }
            hours[bucket.hour] += bucket.seconds
        }
        return hours.enumerated().map { ReadingHourPoint(hour: $0.offset, seconds: $0.element) }
    }

    func recentDays(count: Int, now: Date, calendar: Calendar, bookID: UUID? = nil) -> [ReadingDayPoint] {
        let clamped = max(count, 0)
        let today = calendar.startOfDay(for: now)
        return (0..<clamped).compactMap { offset in
            let daysAgo = clamped - 1 - offset
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }
            let day = ReadingDay(date: date, calendar: calendar)
            return ReadingDayPoint(day: day, seconds: totalSeconds(on: day, bookID: bookID))
        }
    }

    func secondsByDay(inMonthOf date: Date, calendar: Calendar) -> [ReadingDay: TimeInterval] {
        let components = calendar.dateComponents([.year, .month], from: date)
        var result: [ReadingDay: TimeInterval] = [:]
        for bucket in buckets where bucket.day.year == components.year && bucket.day.month == components.month {
            result[bucket.day, default: 0] += bucket.seconds
        }
        return result
    }

    func totalSeconds(on day: ReadingDay, bookID: UUID? = nil) -> TimeInterval {
        buckets.reduce(0) { partial, bucket in
            guard bucket.day == day else { return partial }
            if let bookID, bucket.bookID != bookID { return partial }
            return partial + bucket.seconds
        }
    }

    func checkInCount(inMonthOf date: Date, calendar: Calendar) -> Int {
        secondsByDay(inMonthOf: date, calendar: calendar).values.filter(ReadingCheckIn.qualifies).count
    }

    private func rebuild(_ buckets: [ReadingTimeBucket]) {
        var merged: [ReadingTimeBucket] = []
        var newIndex: [BucketKey: Int] = [:]
        for bucket in buckets {
            merge(
                bookID: bucket.bookID,
                day: bucket.day,
                hour: bucket.hour,
                seconds: bucket.seconds,
                into: &merged,
                index: &newIndex
            )
        }
        self.buckets = merged
        index = newIndex
    }

    private func add(bookID: UUID, day: ReadingDay, hour: Int, seconds: TimeInterval) {
        events.append(ReadingEvent(id: UUID(), bookID: bookID, day: day, hour: hour, seconds: seconds))
        merge(
            bookID: bookID,
            day: day,
            hour: hour,
            seconds: seconds,
            into: &buckets,
            index: &index
        )
    }

    private func merge(
        bookID: UUID,
        day: ReadingDay,
        hour: Int,
        seconds: TimeInterval,
        into buckets: inout [ReadingTimeBucket],
        index: inout [BucketKey: Int]
    ) {
        guard seconds > 0, (0..<24).contains(hour) else { return }
        let key = BucketKey(bookID: bookID, day: day, hour: hour)
        if let existing = index[key] {
            buckets[existing].seconds += seconds
            return
        }
        index[key] = buckets.count
        buckets.append(ReadingTimeBucket(bookID: bookID, day: day, hour: hour, seconds: seconds))
    }

    private static func nextHourBoundary(after date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let start = calendar.date(from: components) ?? date
        return calendar.date(byAdding: .hour, value: 1, to: start) ?? date.addingTimeInterval(3600)
    }
}
