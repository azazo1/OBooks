import SwiftUI

struct FinishBookMenuItem: View {
    let isFinished: Bool
    let onToggleFinished: () -> Void

    var body: some View {
        Button(action: onToggleFinished) {
            Label(
                isFinished ? "取消已读完" : "标记为已读完",
                systemImage: isFinished ? "arrow.uturn.backward" : "checkmark.circle"
            )
        }
    }
}

struct DeleteBookMenuItem: View {
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            Label("删除图书", systemImage: "trash")
        }
    }
}

struct BookActionMenu: View {
    let isFinished: Bool
    let onToggleFinished: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            FinishBookMenuItem(isFinished: isFinished, onToggleFinished: onToggleFinished)
            Divider()
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
        .fixedSize()
        .help("图书操作")
    }
}

extension View {
    func bookContextMenu(
        isFinished: Bool,
        onToggleFinished: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        contextMenu {
            FinishBookMenuItem(isFinished: isFinished, onToggleFinished: onToggleFinished)
            DeleteBookMenuItem(onDelete: onDelete)
        }
    }
}
