import SwiftUI

struct ReadingStatsSection: View {
    @ObservedObject var stats: ReadingStatsLedger

    @State private var visibleMonth = Date()

    private let calendar = Calendar.current
    private let recentDayCount = 14

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            recentCard
            checkInCard
        }
    }

    private var recentCard: some View {
        statsCard {
            HStack(alignment: .firstTextBaseline) {
                Text("近 " + String(recentDayCount) + " 天")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text(ReadingDurationFormat.label(recentTotalSeconds))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(OBooksPalette.accent)
            }
            ReadingDayHistogram(
                points: recentPoints,
                today: ReadingDay(date: Date(), calendar: calendar)
            )
        }
    }

    private var checkInCard: some View {
        statsCard {
            HStack(alignment: .firstTextBaseline) {
                Text("打卡")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text("本月 " + String(monthCheckIns) + " 天")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(OBooksPalette.accent)
            }
            ReadingCheckInCalendar(
                secondsByDay: stats.secondsByDay(inMonthOf: visibleMonth, calendar: calendar),
                month: visibleMonth,
                now: Date(),
                calendar: calendar,
                onPrevious: { shiftMonth(-1) },
                onNext: { shiftMonth(1) }
            )
        }
        .frame(minWidth: 280, maxWidth: 360)
    }

    private var recentPoints: [ReadingDayPoint] {
        stats.recentDays(count: recentDayCount, now: Date(), calendar: calendar)
    }

    private var recentTotalSeconds: TimeInterval {
        recentPoints.reduce(0) { $0 + $1.seconds }
    }

    private var monthCheckIns: Int {
        stats.checkInCount(inMonthOf: visibleMonth, calendar: calendar)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: startOfMonth(visibleMonth)) else {
            return
        }
        let current = startOfMonth(Date())
        visibleMonth = min(next, current)
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func statsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OBooksPalette.section, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
