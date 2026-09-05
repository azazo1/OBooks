import Foundation

struct ReadingDay: Hashable, Codable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    func startOfDay(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date(timeIntervalSince1970: 0)
    }

    static func < (lhs: ReadingDay, rhs: ReadingDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

struct ReadingTimeBucket: Hashable, Codable, Sendable {
    var bookID: UUID
    var day: ReadingDay
    var hour: Int
    var seconds: TimeInterval
}

struct ReadingHourPoint: Hashable, Identifiable, Sendable {
    var hour: Int
    var seconds: TimeInterval

    var id: Int { hour }
}

struct ReadingDayPoint: Hashable, Identifiable, Sendable {
    var day: ReadingDay
    var seconds: TimeInterval

    var id: ReadingDay { day }
}

enum ReadingCheckIn {
    static let minimumSeconds: TimeInterval = 5 * 60

    static func qualifies(_ seconds: TimeInterval) -> Bool {
        seconds >= minimumSeconds
    }
}

enum ReadingDurationFormat {
    static func label(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total == 0 { return "0 分钟" }
        if total < 60 { return "不到 1 分钟" }
        let minutes = total / 60
        if minutes < 60 { return String(minutes) + " 分钟" }
        let hours = minutes / 60
        let remain = minutes % 60
        if remain == 0 { return String(hours) + " 小时" }
        return String(hours) + " 小时 " + String(remain) + " 分钟"
    }
}
