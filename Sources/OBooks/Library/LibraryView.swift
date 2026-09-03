import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum LibraryFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case reading
    case finished
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var filter: LibraryFilter = .all
    @State private var isDropTargeted = false

    private var filteredBooks: [BookSummary] {
        switch filter {
        case .all: return appModel.books
        case .reading: return appModel.books.filter { $0.progressFraction > 0 && $0.progressFraction < 1 }
        case .finished: return appModel.books.filter { $0.progressFraction >= 1 }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Label("全部书籍", systemImage: "books.vertical").tag(LibraryFilter.all)
                Label("正在阅读", systemImage: "book.pages").tag(LibraryFilter.reading)
                Label("已读完", systemImage: "checkmark.circle").tag(LibraryFilter.finished)
            }
            .navigationTitle("OBooks")
            .listStyle(.sidebar)
        } detail: {
            content
        }
        .frame(minWidth: 880, minHeight: 600)
        .sheet(item: $appModel.openBook) { book in
            ReaderView(book: book).environmentObject(appModel)
        }
        .alert("导入失败", isPresented: Binding(
            get: { appModel.alert != nil },
            set: { isPresented in
                if !isPresented { appModel.alert = nil }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(appModel.alert?.message ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filterTitle).font(.title2.weight(.semibold))
                Spacer()
                Button { appModel.importEPUB() } label: { Label("导入 EPUB", systemImage: "plus") }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            Divider()
            if filteredBooks.isEmpty { emptyState } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 28)], spacing: 34) {
                        ForEach(filteredBooks) { book in
                            BookTile(book: book, store: appModel.libraryStore) { appModel.open(book) }
                        }
                    }
                    .padding(32)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var filterTitle: String {
        switch filter {
        case .all: return "全部书籍"
        case .reading: return "正在阅读"
        case .finished: return "已读完"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 46, weight: .light)).foregroundStyle(.secondary)
            Text("书库还是空的").font(.title3.weight(.medium))
            Text("拖入 EPUB 文件, 或使用工具栏导入").foregroundStyle(.secondary)
            Button("导入 EPUB") { appModel.importEPUB() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = NSURL(dataRepresentation: data, relativeTo: nil).filePathURL,
                      url.pathExtension.lowercased() == "epub" else { return }
                Task { @MainActor in appModel.importEPUB(at: url) }
            }
        }
        return true
    }
}

private struct BookTile: View {
    let book: BookSummary
    let store: LibraryStore
    let action: () -> Void
    @State private var image: NSImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                BookCover(book: book, image: image)
                    .aspectRatio(0.68, contentMode: .fit).frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.16), radius: 7, y: 4)
                Text(book.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                Text(book.authorLabel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                ProgressView(value: book.progressFraction).tint(.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: book.id) { image = store.coverImage(for: book) }
        .contextMenu { Button("打开") { action() } }
    }
}

private struct BookCover: View {
    let book: BookSummary
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.85), .teal.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(String(book.title.prefix(1))).font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
