import SwiftUI

struct LibrarySidebar: View {
    @Binding var selection: LibraryDestination
    @Binding var query: String
    var searchFocused: FocusState<Bool>.Binding
    let onImport: () -> Void
    @ObservedObject var sync: SyncCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OBooksPalette.accent)
                    Text("OBooks")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OBooksPalette.tertiaryText)
                    TextField("搜索", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.86))
                        .focused(searchFocused)
                }
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 18)
            .padding(.bottom, 24)

            sidebarSection("OBooks") {
                SidebarRow(destination: .home, selection: $selection)
            }

            sidebarSection("书库") {
                SidebarRow(destination: .all, selection: $selection)
                SidebarRow(destination: .wishlist, selection: $selection)
                SidebarRow(destination: .finished, selection: $selection)
            }

            Spacer(minLength: 18)

            Button { openSettings() } label: {
                Label(sync.status, systemImage: sync.lastError == nil ? "icloud" : "exclamationmark.icloud")
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .help("云同步设置")

            Button(action: onImport) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("导入书籍")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .frame(height: 35)
            }
            .buttonStyle(.plain)
            .help("导入 EPUB")
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
        .frame(width: 202)
        .background(OBooksPalette.sidebar)
    }

    @ViewBuilder
    private func sidebarSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 17)
                .padding(.bottom, 3)
            content()
        }
        .padding(.bottom, 20)
    }
}

private struct SidebarRow: View {
    let destination: LibraryDestination
    @Binding var selection: LibraryDestination

    var body: some View {
        Button {
            selection = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                Text(destination.label)
                    .font(.system(size: 13, weight: selection == destination ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selection == destination ? .white : .white.opacity(0.68))
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 29)
            .background(selection == destination ? OBooksPalette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
