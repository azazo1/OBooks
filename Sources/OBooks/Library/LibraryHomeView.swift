import AppKit
import SwiftUI

struct LibraryHomeView: View {
    let books: [BookSummary]
    let store: LibraryStore
    @ObservedObject var stats: ReadingStatsLedger
    let onOpen: (BookSummary) -> Void
    let onImport: () -> Void
    let onDelete: (BookSummary) -> Void
    let onRemoveLocalDownload: ((BookSummary) -> Void)?
    let onToggleFinished: (BookSummary) -> Void
    let onRemoveFromContinueReading: (BookSummary) -> Void

    private var everywhereDeleteTitle: String {
        onRemoveLocalDownload == nil ? "删除图书" : "从所有设备删除"
    }

    private func localDownloadRemoval(for book: BookSummary) -> (() -> Void)? {
        guard let onRemoveLocalDownload, store.isDownloaded(book) else { return nil }
        return { onRemoveLocalDownload(book) }
    }

    private var continueBooks: [BookSummary] {
        books.filter { !$0.isHiddenFromContinueReading }.sorted { lhs, rhs in
            (lhs.lastOpenedAt ?? lhs.importedAt) > (rhs.lastOpenedAt ?? rhs.importedAt)
        }.prefix(3).map { $0 }
    }

    private var completedBooks: [BookSummary] {
        books.filter(\.isFinished).prefix(10).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                pageHeader
                dailyReadingLine
                shelfSection(title: "继续阅读") {
                    if continueBooks.isEmpty {
                        emptyShelf(message: books.isEmpty ? "导入一本 EPUB, 开始你的阅读" : "暂无继续阅读的图书")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(continueBooks) { book in
                                    ContinueBookCard(
                                        book: book,
                                        store: store,
                                        onDelete: { onDelete(book) },
                                        deleteTitle: everywhereDeleteTitle,
                                        onRemoveLocalDownload: localDownloadRemoval(for: book),
                                        onToggleFinished: { onToggleFinished(book) },
                                        onRemoveFromContinueReading: { onRemoveFromContinueReading(book) }
                                    ) { onOpen(book) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.never)
                    }
                }

                shelfSection(title: "之前读过", showsChevron: !books.isEmpty) {
                    if books.isEmpty {
                        emptyShelf()
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 20) {
                                ForEach(books.prefix(6)) { book in
                                    PreviousBookCard(
                                        book: book,
                                        store: store,
                                        onDelete: { onDelete(book) },
                                        deleteTitle: everywhereDeleteTitle,
                                        onRemoveLocalDownload: localDownloadRemoval(for: book),
                                        onToggleFinished: { onToggleFinished(book) }
                                    ) { onOpen(book) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                shelfSection(title: "本年度读过的书") {
                    if completedBooks.isEmpty {
                        Text("完成一本书后, 它会出现在这里")
                            .font(.system(size: 13))
                            .foregroundStyle(OBooksPalette.secondaryText)
                            .padding(.vertical, 14)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 22)],
                            alignment: .leading, spacing: 26
                        ) {
                            ForEach(completedBooks) { book in
                                CompactBookCard(
                                    book: book,
                                    store: store,
                                    onDelete: { onDelete(book) },
                                    deleteTitle: everywhereDeleteTitle,
                                    onRemoveLocalDownload: localDownloadRemoval(for: book),
                                    onToggleFinished: { onToggleFinished(book) }
                                ) { onOpen(book) }
                            }
                        }
                    }
                }

                shelfSection(title: "阅读目标") {
                    ReadingGoalCard(books: books, stats: stats)
                }

                shelfSection(title: "阅读统计") {
                    ReadingStatsSection(stats: stats)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 35)
            .padding(.bottom, 42)
        }
        .scrollIndicators(.hidden)
        .background(OBooksPalette.window)
    }

    private var pageHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("主页")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                HStack(spacing: 5) {
                    Image(systemName: todayCheckedIn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(OBooksPalette.accent)
                    Text(todayHeaderLabel)
                        .foregroundStyle(OBooksPalette.accent)
                }
                .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            Button(action: onImport) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .buttonStyle(
                OBooksIconButtonStyle(size: 34, cornerRadius: 8, normalBackgroundOpacity: 0.08)
            )
            .help("导入 EPUB")
        }
    }

    private var todaySeconds: TimeInterval {
        stats.totalSeconds(on: ReadingDay(date: Date(), calendar: .current))
    }

    private var todayCheckedIn: Bool {
        ReadingCheckIn.qualifies(todaySeconds)
    }

    private var todayHeaderLabel: String {
        todaySeconds > 0
            ? "今日阅读 " + ReadingDurationFormat.label(todaySeconds)
            : "今天还没有开始阅读"
    }

    private var dailyReadingLine: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(OBooksPalette.accent)
                .frame(width: 3, height: 21)
            VStack(alignment: .leading, spacing: 2) {
                Text("坚持每天阅读")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Text("用安静的时间, 读完手边的书")
                    .font(.system(size: 12))
                    .foregroundStyle(OBooksPalette.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func shelfSection<Content: View>(
        title: String, showsChevron: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OBooksPalette.secondaryText)
                }
            }
            content()
        }
    }

    private func emptyShelf(message: String = "导入一本 EPUB, 开始你的阅读") -> some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 18))
                .foregroundStyle(OBooksPalette.secondaryText)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(OBooksPalette.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
        .background(OBooksPalette.section, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct ContinueBookCard: View {
    let book: BookSummary
    let store: LibraryStore
    let onDelete: () -> Void
    var deleteTitle: String = "删除图书"
    var onRemoveLocalDownload: (() -> Void)? = nil
    let onToggleFinished: () -> Void
    let onRemoveFromContinueReading: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    BookCoverImage(book: book, store: store)
                        .frame(width: 48, height: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(book.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                            .frame(height: 32, alignment: .center)
                        Text(book.authorLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                        Group {
                            if book.isFinished {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(OBooksPalette.secondaryText)
                                    Text("已读完")
                                        .foregroundStyle(OBooksPalette.secondaryText)
                                }
                                .font(.system(size: 10, weight: .semibold))
                            } else {
                                HStack(spacing: 7) {
                                    ProgressView(value: book.progressFraction)
                                        .progressViewStyle(.linear)
                                        .tint(OBooksPalette.accent)
                                        .frame(width: 86)
                                    Text("\(Int(book.progressFraction * 100))%")
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.58))
                                }
                            }
                        }
                        .frame(height: 16, alignment: .leading)
                    }
                    Spacer(minLength: 4)
                }
                .padding(12)
                .frame(width: 232, height: 94)

                if book.isNearCompletion {
                    Color.black.opacity(0.08)
                        .frame(height: 36)
                }
            }
            .frame(width: 232, height: book.isNearCompletion ? 130 : 94)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .background(OBooksPalette.card, in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .bottomLeading) {
            if book.isNearCompletion {
                Button(action: onToggleFinished) {
                    Label("标记为已读完", systemImage: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                .frame(height: 36)
            }
        }
        .overlay(alignment: .topTrailing) {
            BookActionMenu(
                isFinished: book.isFinished,
                onToggleFinished: onToggleFinished,
                onDelete: onDelete,
                deleteTitle: deleteTitle,
                onRemoveLocalDownload: onRemoveLocalDownload,
                onRemoveFromContinueReading: onRemoveFromContinueReading
            )
            .padding(6)
        }
        .bookContextMenu(
            isFinished: book.isFinished,
            onToggleFinished: onToggleFinished,
            onDelete: onDelete,
            deleteTitle: deleteTitle,
            onRemoveLocalDownload: onRemoveLocalDownload,
            onRemoveFromContinueReading: onRemoveFromContinueReading
        )
    }
}

private struct PreviousBookCard: View {
    let book: BookSummary
    let store: LibraryStore
    let onDelete: () -> Void
    var deleteTitle: String = "删除图书"
    var onRemoveLocalDownload: (() -> Void)? = nil
    let onToggleFinished: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                BookCoverImage(book: book, store: store)
                    .frame(width: 116, height: 164)
                Text(book.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.87))
                    .lineLimit(2)
                Text(book.authorLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(OBooksPalette.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 116, alignment: .leading)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            BookActionMenu(
                isFinished: book.isFinished,
                onToggleFinished: onToggleFinished,
                onDelete: onDelete,
                deleteTitle: deleteTitle,
                onRemoveLocalDownload: onRemoveLocalDownload
            )
            .padding(6)
        }
        .bookContextMenu(
            isFinished: book.isFinished,
            onToggleFinished: onToggleFinished,
            onDelete: onDelete,
            deleteTitle: deleteTitle,
            onRemoveLocalDownload: onRemoveLocalDownload
        )
    }
}

private struct CompactBookCard: View {
    let book: BookSummary
    let store: LibraryStore
    let onDelete: () -> Void
    var deleteTitle: String = "删除图书"
    var onRemoveLocalDownload: (() -> Void)? = nil
    let onToggleFinished: () -> Void
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                BookCoverImage(book: book, store: store)
                    .frame(width: 116, height: 164)
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 4) {
                Button(action: action) {
                    Text(book.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                BookActionMenu(
                    isFinished: book.isFinished,
                    onToggleFinished: onToggleFinished,
                    onDelete: onDelete,
                    deleteTitle: deleteTitle,
                    onRemoveLocalDownload: onRemoveLocalDownload
                )
                .frame(width: 34, height: 34)
            }
            .frame(width: 116, alignment: .leading)
        }
        .bookContextMenu(
            isFinished: book.isFinished,
            onToggleFinished: onToggleFinished,
            onDelete: onDelete,
            deleteTitle: deleteTitle,
            onRemoveLocalDownload: onRemoveLocalDownload
        )
    }
}

struct BookCoverImage: View {
    let book: BookSummary
    let store: LibraryStore
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        BookCoverImageBody(book: book, store: store, sync: appModel.sync)
    }
}

private struct BookCoverImageBody: View {
    let book: BookSummary
    let store: LibraryStore
    @ObservedObject var sync: SyncCoordinator
    @State private var image: NSImage?
    @State private var isDownloaded = true
    @State private var hoveringBadge = false

    private var isDownloading: Bool { sync.downloading.contains(book.id) }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    coverColor
                    Text(String(book.title.prefix(1)))
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .bottomTrailing) {
            coverDownloadBadge
        }
        .task(id: book.id) {
            image = store.coverImage(for: book)
            isDownloaded = store.isDownloaded(book)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookAssetsChanged)) { notification in
            guard notification.object as? String == book.canonicalID else { return }
            image = store.coverImage(for: book)
            isDownloaded = store.isDownloaded(book)
        }
        .onChange(of: isDownloading) { _, downloading in
            if !downloading {
                hoveringBadge = false
                isDownloaded = store.isDownloaded(book)
            }
        }
    }

    @ViewBuilder
    private var coverDownloadBadge: some View {
        if isDownloading {
            Button {
                sync.cancelDownload(book.id)
            } label: {
                downloadBadgeChrome {
                    if hoveringBadge {
                        Image(systemName: "xmark")
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(2)
                    } else {
                        DownloadPieProgress(progress: sync.downloadProgress[book.id])
                    }
                }
            }
            .buttonStyle(.plain)
            .help(hoveringBadge ? "取消下载" : "正在下载")
            .onHover { hoveringBadge = $0 }
        } else if !isDownloaded {
            downloadBadgeChrome {
                Image(systemName: "icloud.and.arrow.down")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
            }
            .help("打开时下载")
        }
    }

    private func downloadBadgeChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 14, height: 14)
            .padding(6)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            .padding(5)
            .contentShape(Rectangle())
    }

    private var coverColor: Color {
        let value = book.title.utf8.reduce(0) { partial, byte in partial + Int(byte) }
        let colors: [Color] = [
            Color(red: 0.24, green: 0.33, blue: 0.42),
            Color(red: 0.35, green: 0.25, blue: 0.28),
            Color(red: 0.28, green: 0.36, blue: 0.30),
            Color(red: 0.39, green: 0.31, blue: 0.22),
        ]
        return colors[value % colors.count]
    }
}

private struct DownloadPieProgress: View {
    var progress: Double?
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.22))
            if let progress {
                PieSlice(progress: min(max(progress, 0), 1))
                    .fill(OBooksPalette.accent)
            } else {
                PieSlice(progress: 0.22)
                    .fill(OBooksPalette.accent)
                    .rotationEffect(.degrees(rotation))
            }
        }
        .onAppear {
            guard progress == nil else { return }
            rotation = 0
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

private struct PieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
