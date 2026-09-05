import AppKit
import SwiftUI

struct ReaderOpeningOverlay: View {
    let book: BookSummary
    private let image: NSImage?

    init(book: BookSummary, store: LibraryStore) {
        self.book = book
        self.image = store.coverImage(for: book)
    }

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 28) {
                cover
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white.opacity(0.82))
            }
            .offset(y: -12)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在打开 \(book.title)")
    }

    private var cover: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    placeholderColor
                    Text(String(book.title.prefix(1)))
                        .font(.system(size: 64, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
        .frame(width: 248, height: 372)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 28, y: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var placeholderColor: Color {
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
