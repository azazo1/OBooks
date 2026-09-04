import AppKit
import SwiftUI

struct LibraryHomeView: View {
    let books: [BookSummary]
    let store: LibraryStore
    let onOpen: (BookSummary) -> Void
    let onImport: () -> Void
    let onDelete: (BookSummary) -> Void
    let onToggleFinished: (BookSummary) -> Void

    private var continueBooks: [BookSummary] {
        books.sorted { lhs, rhs in
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
                        emptyShelf
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(continueBooks) { book in
                                    ContinueBookCard(
                                        book: book,
                                        store: store,
                                        onDelete: { onDelete(book) },
                                        onToggleFinished: { onToggleFinished(book) }
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
                        emptyShelf
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 20) {
                                ForEach(books.prefix(6)) { book in
                                    PreviousBookCard(
                                        book: book,
                                        store: store,
                                        onDelete: { onDelete(book) },
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
                                    onToggleFinished: { onToggleFinished(book) }
                                ) { onOpen(book) }
                            }
                        }
                    }
                }

                shelfSection(title: "阅读目标") {
                    ReadingGoalCard(books: books)
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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OBooksPalette.accent)
                    Text("今日阅读进度")
                        .foregroundStyle(OBooksPalette.accent)
                    Text("目标已达成")
                        .foregroundStyle(OBooksPalette.secondaryText)
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

    private var emptyShelf: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 18))
                .foregroundStyle(OBooksPalette.secondaryText)
            Text("导入一本 EPUB, 开始你的阅读")
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
    let onToggleFinished: () -> Void
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
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
            }
            .buttonStyle(.plain)

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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .frame(height: 36)
                .background(Color.black.opacity(0.08))
            }
        }
        .frame(width: 232, height: book.isNearCompletion ? 130 : 94)
        .background(OBooksPalette.card, in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .topTrailing) {
            BookActionMenu(
                isFinished: book.isFinished,
                onToggleFinished: onToggleFinished,
                onDelete: onDelete
            )
            .padding(6)
        }
        .bookContextMenu(
            isFinished: book.isFinished,
            onToggleFinished: onToggleFinished,
            onDelete: onDelete
        )
    }
}

private struct PreviousBookCard: View {
    let book: BookSummary
    let store: LibraryStore
    let onDelete: () -> Void
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
                onDelete: onDelete
            )
            .padding(6)
        }
        .bookContextMenu(
            isFinished: book.isFinished,
            onToggleFinished: onToggleFinished,
            onDelete: onDelete
        )
    }
}

private struct CompactBookCard: View {
    let book: BookSummary
    let store: LibraryStore
    let onDelete: () -> Void
    let onToggleFinished: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                BookCoverImage(book: book, store: store)
                    .frame(width: 116, height: 164)
                Text(book.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)
            }
            .frame(width: 116, alignment: .leading)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            BookActionMenu(
                isFinished: book.isFinished,
                onToggleFinished: onToggleFinished,
                onDelete: onDelete
            )
            .padding(6)
        }
        .bookContextMenu(
            isFinished: book.isFinished,
            onToggleFinished: onToggleFinished,
            onDelete: onDelete
        )
    }
}

struct BookCoverImage: View {
    let book: BookSummary
    let store: LibraryStore
    @State private var image: NSImage?

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
        .task(id: book.id) {
            image = store.coverImage(for: book)
        }
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
