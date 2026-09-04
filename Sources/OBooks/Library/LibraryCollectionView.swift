import SwiftUI

struct LibraryCollectionView: View {
    let destination: LibraryDestination
    let books: [BookSummary]
    let store: LibraryStore
    let onOpen: (BookSummary) -> Void
    let onImport: () -> Void
    let onDelete: (BookSummary) -> Void
    let onToggleFinished: (BookSummary) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(destination.label)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white.opacity(0.94))
                        Text("\(books.count) 本书")
                            .font(.system(size: 12))
                            .foregroundStyle(OBooksPalette.secondaryText)
                    }
                    Spacer()
                    Button(action: onImport) {
                        Label("导入 EPUB", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OBooksPalette.accent)
                }

                if books.isEmpty {
                    collectionEmptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 28)],
                        alignment: .leading, spacing: 30
                    ) {
                        ForEach(books) { book in
                            CollectionBookCard(
                                book: book,
                                store: store,
                                onDelete: { onDelete(book) },
                                onToggleFinished: { onToggleFinished(book) }
                            ) {
                                onOpen(book)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 35)
            .padding(.bottom, 42)
        }
        .scrollIndicators(.hidden)
        .background(OBooksPalette.window)
    }

    private var collectionEmptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: destination == .finished ? "checkmark.circle" : "books.vertical")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(OBooksPalette.secondaryText)
            Text(destination == .finished ? "还没有读完的书" : "这里还没有书")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
            Text("使用左下角的导入按钮添加 EPUB")
                .font(.system(size: 12))
                .foregroundStyle(OBooksPalette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(OBooksPalette.section, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CollectionBookCard: View {
    let book: BookSummary
    let store: LibraryStore
    let onDelete: () -> Void
    let onToggleFinished: () -> Void
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: action) {
                BookCoverImage(book: book, store: store)
                    .aspectRatio(0.68, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
            }
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 8) {
                Button(action: action) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                BookActionMenu(
                    isFinished: book.isFinished,
                    onToggleFinished: onToggleFinished,
                    onDelete: onDelete
                )
                    .frame(width: 34, height: 34)
            }
            .padding(.top, 5)

            HStack(alignment: .center, spacing: 8) {
                Button(action: action) {
                    Text(book.authorLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(OBooksPalette.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Text("\(Int(book.progressFraction * 100))%")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(OBooksPalette.secondaryText)
                    .frame(width: 30, alignment: .center)
            }
        }
        .bookContextMenu(
            isFinished: book.isFinished,
            onToggleFinished: onToggleFinished,
            onDelete: onDelete
        )
    }
}
