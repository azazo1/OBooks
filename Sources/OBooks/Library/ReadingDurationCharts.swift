import SwiftUI

struct ReadingHourHistogram: View {
    let points: [ReadingHourPoint]
    let currentHour: Int

    var body: some View {
        ReadingBarPlot(
            seconds: points.map(\.seconds),
            labels: points.map { [0, 6, 12, 18].contains($0.hour) ? String($0.hour) : "" },
            highlights: points.map { $0.hour == currentHour },
            helpText: { index, seconds in
                String(format: "%02d:00, ", index) + ReadingDurationFormat.label(seconds)
            }
        )
    }
}

struct ReadingDayHistogram: View {
    let points: [ReadingDayPoint]
    let today: ReadingDay

    var body: some View {
        ReadingBarPlot(
            seconds: points.map(\.seconds),
            labels: points.map { dayLabel($0.day) },
            highlights: points.map { $0.day == today },
            helpText: { index, seconds in
                guard points.indices.contains(index) else {
                    return ReadingDurationFormat.label(seconds)
                }
                return dateLabel(points[index].day) + ", " + ReadingDurationFormat.label(seconds)
            }
        )
    }

    private func dayLabel(_ day: ReadingDay) -> String {
        String(day.day)
    }

    private func dateLabel(_ day: ReadingDay) -> String {
        String(day.month) + " 月 " + String(day.day) + " 日"
    }
}

private struct ReadingBarPlot: View {
    let seconds: [TimeInterval]
    let labels: [String]
    let highlights: [Bool]
    let helpText: (Int, TimeInterval) -> String

    private let chartHeight: CGFloat = 92

    var body: some View {
        let peak = max(seconds.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(seconds.enumerated()), id: \.offset) { index, value in
                    let ratio = CGFloat(value / peak)
                    let filled = value > 0
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor(filled: filled, highlighted: highlights.indices.contains(index) && highlights[index]))
                        .frame(maxWidth: .infinity, minHeight: 4, maxHeight: max(4, chartHeight * max(ratio, filled ? 0.04 : 0)))
                        .frame(height: chartHeight, alignment: .bottom)
                        .help(helpText(index, value))
                }
            }
            HStack(spacing: 3) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(OBooksPalette.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barColor(filled: Bool, highlighted: Bool) -> Color {
        if filled { return OBooksPalette.accent.opacity(highlighted ? 1 : 0.82) }
        return Color.white.opacity(highlighted ? 0.16 : 0.08)
    }
}
