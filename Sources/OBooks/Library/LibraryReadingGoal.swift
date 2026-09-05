import SwiftUI

struct ReadingGoalCard: View {
    let books: [BookSummary]
    @ObservedObject var stats: ReadingStatsLedger

    @State private var selectedBookID: UUID?

    private let dailyGoalSeconds: TimeInterval = 30 * 60
    private let calendar = Calendar.current

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 7)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(OBooksPalette.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 6) {
                    Text("今日阅读")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(ReadingDurationFormat.label(todaySeconds))
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(OBooksPalette.accent)
                    Text("目标 " + ReadingDurationFormat.label(dailyGoalSeconds))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(OBooksPalette.secondaryText)
                }
            }
            .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    bookPicker
                    Spacer()
                    Text(ReadingDurationFormat.label(todayBookSeconds))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(OBooksPalette.accent)
                }
                if books.isEmpty {
                    Text("导入一本书并开始阅读后, 这里会显示时长统计")
                        .font(.system(size: 12))
                        .foregroundStyle(OBooksPalette.secondaryText)
                        .padding(.vertical, 18)
                } else {
                    ReadingHourHistogram(
                        points: hourPoints,
                        currentHour: calendar.component(.hour, from: Date())
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(OBooksPalette.section, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .onAppear(perform: resolveSelection)
        .onChange(of: books.map(\.id)) { _, _ in
            resolveSelection()
        }
    }

    private var todaySeconds: TimeInterval {
        stats.totalSeconds(on: ReadingDay(date: Date(), calendar: calendar))
    }

    private var progress: Double {
        guard dailyGoalSeconds > 0 else { return 0 }
        return min(1, todaySeconds / dailyGoalSeconds)
    }

    private var bookPicker: some View {
        Menu {
            ForEach(books) { book in
                Button(book.title) {
                    selectedBookID = book.id
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedBook?.title ?? "选择书籍")
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .disabled(books.isEmpty)
    }

    private var selectedBook: BookSummary? {
        books.first(where: { $0.id == resolvedBookID })
    }

    private var resolvedBookID: UUID? {
        if let selectedBookID, books.contains(where: { $0.id == selectedBookID }) {
            return selectedBookID
        }
        return defaultBookID
    }

    private var defaultBookID: UUID? {
        let today = ReadingDay(date: Date(), calendar: calendar)
        if let ranked = books.max(by: {
            stats.totalSeconds(on: today, bookID: $0.id) < stats.totalSeconds(on: today, bookID: $1.id)
        }), stats.totalSeconds(on: today, bookID: ranked.id) > 0 {
            return ranked.id
        }
        return books.max {
            ($0.lastOpenedAt ?? $0.importedAt) < ($1.lastOpenedAt ?? $1.importedAt)
        }?.id
    }

    private var hourPoints: [ReadingHourPoint] {
        guard let bookID = resolvedBookID else {
            return (0..<24).map { ReadingHourPoint(hour: $0, seconds: 0) }
        }
        return stats.todayHours(bookID: bookID, now: Date(), calendar: calendar)
    }

    private var todayBookSeconds: TimeInterval {
        guard let bookID = resolvedBookID else { return 0 }
        return stats.totalSeconds(on: ReadingDay(date: Date(), calendar: calendar), bookID: bookID)
    }

    private func resolveSelection() {
        if let selectedBookID, books.contains(where: { $0.id == selectedBookID }) {
            return
        }
        selectedBookID = defaultBookID
    }
}
