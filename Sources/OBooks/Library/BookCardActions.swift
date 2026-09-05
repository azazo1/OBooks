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

struct DeleteBookMenuItem: View {
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            Label("删除图书", systemImage: "trash")
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

struct BookActionMenu: View {
    let isFinished: Bool
    let onToggleFinished: () -> Void
    let onDelete: () -> Void
    var onRemoveFromContinueReading: (() -> Void)? = nil

    var body: some View {
        Menu {
            FinishBookMenuItem(isFinished: isFinished, onToggleFinished: onToggleFinished)
            if let onRemoveFromContinueReading {
                RemoveFromContinueReadingMenuItem(onRemove: onRemoveFromContinueReading)
            }
            Divider()
            DeleteBookMenuItem(onDelete: onDelete)
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
        onRemoveFromContinueReading: (() -> Void)? = nil
    ) -> some View {
        contextMenu {
            FinishBookMenuItem(isFinished: isFinished, onToggleFinished: onToggleFinished)
            if let onRemoveFromContinueReading {
                RemoveFromContinueReadingMenuItem(onRemove: onRemoveFromContinueReading)
            }
            DeleteBookMenuItem(onDelete: onDelete)
        }
    }
}
