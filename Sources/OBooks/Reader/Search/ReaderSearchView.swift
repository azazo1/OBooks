import SwiftUI

struct ReaderSearchView: View {
    @ObservedObject var session: ReaderSearchSession
    let isPaging: Bool
    let pageCount: Int
    var focusedField: FocusState<ReaderPanel?>.Binding
    let onSelect: (ReaderSearchHit) -> Void
    let onJumpToPage: (Int) -> Void

    private var trimmedQuery: String {
        session.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pageJump: Int? {
        guard isPaging, let page = Int(trimmedQuery), (1...max(pageCount, 1)).contains(page) else {
            return nil
        }
        return page
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField
            if trimmedQuery.isEmpty {
                recentSection
            } else {
                resultHeader
                if let pageJump {
                    pageJumpRow(pageJump)
                }
                resultBody
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: session.isSearching) { _, searching in
            guard !searching, let hit = session.consumePendingReveal() else { return }
            onSelect(hit)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("输入一个字词或页码", text: queryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .focused(focusedField, equals: .search)
                .onSubmit(submitSearch)
            if !session.query.isEmpty {
                Button {
                    session.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(OBooksIconButtonStyle(size: 26, cornerRadius: 7))
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.13), lineWidth: 1)
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { session.query },
            set: { session.updateQuery($0) }
        )
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近搜索")
                Spacer()
                if !session.recentQueries.isEmpty {
                    Button("清除") { session.clearRecent() }
                        .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

            if session.recentQueries.isEmpty {
                Text("输入关键词开始搜索")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.recentQueries, id: \.self) { item in
                        Button {
                            session.applyRecent(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
    }

    private var resultHeader: some View {
        HStack(spacing: 8) {
            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !session.results.isEmpty {
                Text(selectionLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Button {
                    if let hit = session.selectPrevious() {
                        onSelect(hit)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(OBooksIconButtonStyle(size: 24, cornerRadius: 6))
                .help("上一个匹配")
                Button {
                    if let hit = session.selectNext() {
                        onSelect(hit)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(OBooksIconButtonStyle(size: 24, cornerRadius: 6))
                .help("下一个匹配")
            }
        }
    }

    private var resultBody: some View {
        Group {
            if session.results.isEmpty {
                if session.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在搜索全书")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    Spacer()
                } else if pageJump == nil {
                    Text("未找到匹配内容")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    Spacer()
                } else {
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.results) { hit in
                            resultRow(hit)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pageJumpRow(_ page: Int) -> some View {
        Button {
            onJumpToPage(page)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .foregroundStyle(OBooksPalette.accent)
                Text("跳转到本章第 \(page) 页")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resultRow(_ hit: ReaderSearchHit) -> some View {
        Button {
            session.select(hit)
            onSelect(hit)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(hit.chapterTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                snippetText(hit)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                hit.id == session.selectedHitID
                    ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                    : Color.primary.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hit.chapterTitle), \(hit.snippet)")
    }

    private func snippetText(_ hit: ReaderSearchHit) -> Text {
        let snippet = hit.snippet as NSString
        let range = NSIntersectionRange(
            hit.matchRangeInSnippet,
            NSRange(location: 0, length: snippet.length)
        )
        guard range.length > 0, let matchRange = Range(range, in: hit.snippet) else {
            return Text(hit.snippet).foregroundStyle(.primary)
        }
        let prefix = String(hit.snippet[hit.snippet.startIndex..<matchRange.lowerBound])
        let match = String(hit.snippet[matchRange])
        let suffix = String(hit.snippet[matchRange.upperBound..<hit.snippet.endIndex])
        return Text(prefix).foregroundStyle(.primary)
            + Text(match).foregroundStyle(OBooksPalette.accent).fontWeight(.semibold)
            + Text(suffix).foregroundStyle(.primary)
    }

    private func submitSearch() {
        if let hit = session.submit() {
            onSelect(hit)
            return
        }
        if let pageJump, !session.isSearching, session.results.isEmpty {
            onJumpToPage(pageJump)
        }
    }

    private var statusText: String {
        if session.isSearching, session.results.isEmpty {
            return "正在搜索"
        }
        if session.results.isEmpty {
            return pageJump == nil ? "无匹配" : "页码"
        }
        if session.didTruncate {
            return "显示前 \(session.results.count) 个匹配"
        }
        return "\(session.results.count) 个匹配"
    }

    private var selectionLabel: String {
        guard let selectedHitID = session.selectedHitID,
              let index = session.results.firstIndex(where: { $0.id == selectedHitID })
        else {
            return "\(session.results.count)"
        }
        return "\(index + 1) / \(session.results.count)"
    }
}
