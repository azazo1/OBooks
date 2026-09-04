import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum LibraryDestination: String, CaseIterable, Hashable, Identifiable {
    case home
    case all
    case wishlist
    case finished

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "主页"
        case .all: return "全部"
        case .wishlist: return "欲读清单"
        case .finished: return "已读完"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .all: return "books.vertical"
        case .wishlist: return "arrow.right.circle"
        case .finished: return "checkmark.circle"
        }
    }
}

enum OBooksPalette {
    static let window = Color(red: 0.105, green: 0.105, blue: 0.105)
    static let sidebar = Color(red: 0.125, green: 0.125, blue: 0.115)
    static let selected = Color(red: 0.28, green: 0.28, blue: 0.25)
    static let section = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let card = Color(red: 0.235, green: 0.235, blue: 0.235)
    static let cardEmphasis = Color(red: 0.48, green: 0.46, blue: 0.44)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)
    static let accent = Color(red: 0.29, green: 0.62, blue: 0.94)
}

struct LibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var destination: LibraryDestination = .home
    @State private var query = ""
    @State private var isDropTargeted = false
    @State private var bookPendingDeletion: BookSummary?

    private var visibleBooks: [BookSummary] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = appModel.books.filter { book in
            query.isEmpty || book.title.localizedCaseInsensitiveContains(query) || book.authorLabel.localizedCaseInsensitiveContains(query)
        }
        switch destination {
        case .home, .all:
            return matching
        case .wishlist:
            return matching.filter { $0.progressFraction == 0 }
        case .finished:
            return matching.filter(\.isFinished)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar(selection: $destination, query: $query, onImport: appModel.importEPUB)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
            if destination == .home {
                LibraryHomeView(
                    books: visibleBooks,
                    store: appModel.libraryStore,
                    onOpen: appModel.open,
                    onImport: appModel.importEPUB,
                    onDelete: requestDelete,
                    onToggleFinished: { appModel.toggleFinished(for: $0.id) }
                )
            } else {
                LibraryCollectionView(
                    destination: destination,
                    books: visibleBooks,
                    store: appModel.libraryStore,
                    onOpen: appModel.open,
                    onImport: appModel.importEPUB,
                    onDelete: requestDelete,
                    onToggleFinished: { appModel.toggleFinished(for: $0.id) }
                )
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .background(OBooksPalette.window)
        .preferredColorScheme(.dark)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(OBooksPalette.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .alert(
            appModel.alert?.title ?? "提示",
            isPresented: Binding(
                get: { appModel.alert != nil },
                set: { isPresented in
                    if !isPresented { appModel.alert = nil }
                }
            )
        ) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(appModel.alert?.message ?? "")
        }
        .confirmationDialog(
            "删除图书",
            isPresented: Binding(
                get: { bookPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { bookPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let book = bookPendingDeletion else { return }
                bookPendingDeletion = nil
                appModel.delete(book)
            }
            Button("取消", role: .cancel) {
                bookPendingDeletion = nil
            }
        } message: {
            Text("确定删除 \(bookPendingDeletion?.title ?? "这本书") 及其本地文件")
        }
    }

    private func requestDelete(_ book: BookSummary) {
        bookPendingDeletion = book
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let url = NSURL(dataRepresentation: data, relativeTo: nil).filePathURL,
                      url.pathExtension.lowercased() == "epub" else { return }
                Task { @MainActor in
                    appModel.importEPUB(at: url)
                }
            }
        }
        return true
    }
}
