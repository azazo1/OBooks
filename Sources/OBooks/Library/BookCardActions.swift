import SwiftUI

struct FinishBookMenuItem: View {
    let isFinished: Bool
    let onToggleFinished: () -> Void

    var body: some View {
        Button(action: onToggleFinished) {
            Label(
                isFinished ? "标记为仍在读" : "标记为已读完",
                systemImage: isFinished ? "arrow.uturn.backward" : "checkmark.circle"
            )
        }
    }
}

struct RemoveLocalDownloadMenuItem: View {
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            Label("删除本机文件", systemImage: "internaldrive")
        }
    }
}

struct DeleteBookMenuItem: View {
    var title: String = "删除图书"
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            Label(title, systemImage: "trash")
        }
    }
}

struct RemoveFromContinueReadingMenuItem: View {
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            Label("从继续阅读中移除", systemImage: "minus.circle")
        }
    }
}

@ViewBuilder
private func bookActionMenuContent(
    isFinished: Bool,
    onToggleFinished: @escaping () -> Void,
    onDelete: @escaping () -> Void,
    deleteTitle: String = "删除图书",
    onRemoveLocalDownload: (() -> Void)? = nil,
    onRemoveFromContinueReading: (() -> Void)? = nil
) -> some View {
    FinishBookMenuItem(isFinished: isFinished, onToggleFinished: onToggleFinished)
    if let onRemoveFromContinueReading {
        RemoveFromContinueReadingMenuItem(onRemove: onRemoveFromContinueReading)
    }
    Divider()
    if let onRemoveLocalDownload {
        RemoveLocalDownloadMenuItem(onRemove: onRemoveLocalDownload)
    }
    DeleteBookMenuItem(title: deleteTitle, onDelete: onDelete)
}

struct BookActionMenu: View {
    let isFinished: Bool
    let onToggleFinished: () -> Void
    let onDelete: () -> Void
    var deleteTitle: String = "删除图书"
    var onRemoveLocalDownload: (() -> Void)? = nil
    var onRemoveFromContinueReading: (() -> Void)? = nil

    var body: some View {
        Menu {
            bookActionMenuContent(
                isFinished: isFinished,
                onToggleFinished: onToggleFinished,
                onDelete: onDelete,
                deleteTitle: deleteTitle,
                onRemoveLocalDownload: onRemoveLocalDownload,
                onRemoveFromContinueReading: onRemoveFromContinueReading
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.68), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(OBooksIconButtonStyle(size: 34, cornerRadius: 17))
        .fixedSize()
        .help("图书操作")
    }
}

extension View {
    func bookContextMenu(
        isFinished: Bool,
        onToggleFinished: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        deleteTitle: String = "删除图书",
        onRemoveLocalDownload: (() -> Void)? = nil,
        onRemoveFromContinueReading: (() -> Void)? = nil
    ) -> some View {
        contextMenu {
            bookActionMenuContent(
                isFinished: isFinished,
                onToggleFinished: onToggleFinished,
                onDelete: onDelete,
                deleteTitle: deleteTitle,
                onRemoveLocalDownload: onRemoveLocalDownload,
                onRemoveFromContinueReading: onRemoveFromContinueReading
            )
        }
    }
}
