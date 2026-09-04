import SwiftUI

struct DeleteBookMenuItem: View {
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            Label("删除图书", systemImage: "trash")
        }
    }
}

struct BookActionMenu: View {
    let onDelete: () -> Void

    var body: some View {
        Menu {
            DeleteBookMenuItem(onDelete: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.68), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("图书操作")
    }
}

extension View {
    func bookContextMenu(onDelete: @escaping () -> Void) -> some View {
        contextMenu {
            DeleteBookMenuItem(onDelete: onDelete)
        }
    }
}
