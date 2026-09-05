import SwiftUI

struct ReadingCheckInCalendar: View {
    let secondsByDay: [ReadingDay: TimeInterval]
    let month: Date
    let now: Date
    let calendar: Calendar
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(OBooksIconButtonStyle(size: 26, cornerRadius: 6, normalBackgroundOpacity: 0.06))
                .help("上个月")
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(canGoNext ? 0.72 : 0.28))
                }
                .buttonStyle(OBooksIconButtonStyle(size: 26, cornerRadius: 6, normalBackgroundOpacity: 0.06))
                .disabled(!canGoNext)
                .help("下个月")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OBooksPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    calendarCell(cell)
                }
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: month)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        guard symbols.indices.contains(start) else { return symbols }
        return Array(symbols[start...]) + Array(symbols[..<start])
    }

    private var canGoNext: Bool {
        let current = calendar.dateComponents([.year, .month], from: now)
        let visible = calendar.dateComponents([.year, .month], from: month)
        if (visible.year ?? 0) != (current.year ?? 0) {
            return (visible.year ?? 0) < (current.year ?? 0)
        }
        return (visible.month ?? 0) < (current.month ?? 0)
    }

    private var cells: [DayCell] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: first) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result: [DayCell] = Array(repeating: .empty, count: leading)
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: first) else { continue }
            let readingDay = ReadingDay(date: date, calendar: calendar)
            result.append(
                DayCell(
                    day: readingDay,
                    seconds: secondsByDay[readingDay] ?? 0,
                    isToday: readingDay == ReadingDay(date: now, calendar: calendar),
                    isFuture: date > now
                )
            )
        }
        return result
    }

    @ViewBuilder
    private func calendarCell(_ cell: DayCell) -> some View {
        if let day = cell.day {
            Text(String(day.day))
                .font(.system(size: 11, weight: cell.isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(cell.isFuture ? OBooksPalette.tertiaryText : .white.opacity(0.86))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(fill(for: cell.seconds), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if cell.isToday {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(OBooksPalette.accent.opacity(0.9), lineWidth: 1)
                    }
                }
                .help(String(day.month) + " 月 " + String(day.day) + " 日, " + ReadingDurationFormat.label(cell.seconds))
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        }
    }

    private func fill(for seconds: TimeInterval) -> Color {
        guard ReadingCheckIn.qualifies(seconds) else { return Color.white.opacity(0.05) }
        if seconds < 15 * 60 { return OBooksPalette.accent.opacity(0.28) }
        if seconds < 30 * 60 { return OBooksPalette.accent.opacity(0.5) }
        if seconds < 60 * 60 { return OBooksPalette.accent.opacity(0.72) }
        return OBooksPalette.accent
    }
}

private struct DayCell {
    var day: ReadingDay?
    var seconds: TimeInterval
    var isToday: Bool
    var isFuture: Bool

    static let empty = DayCell(day: nil, seconds: 0, isToday: false, isFuture: false)
}
