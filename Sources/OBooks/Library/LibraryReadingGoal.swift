import SwiftUI

struct ReadingGoalCard: View {
    let books: [BookSummary]

    private var completedCount: Int {
        books.filter { $0.progressFraction >= 1 }.count
    }

    private var progress: Double {
        min(1, Double(completedCount) / 10)
    }

    var body: some View {
        HStack(spacing: 34) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(OBooksPalette.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text("今日阅读进度")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                    Image(systemName: progress >= 1 ? "checkmark" : "book.closed")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OBooksPalette.accent)
                    Text(progressText)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(OBooksPalette.secondaryText)
                }
            }
            .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: 9) {
                Text("保持阅读节奏")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("每完成一本书, 这里会记录你的阅读进度")
                    .font(.system(size: 12))
                    .foregroundStyle(OBooksPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(completedLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OBooksPalette.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(OBooksPalette.section, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var progressText: String {
        String(Int(progress * 100)) + "%"
    }

    private var completedLabel: String {
        completedCount == 0 ? "还没有完成的书" : "已读完 " + String(completedCount) + " 本"
    }
}
