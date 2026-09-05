import SwiftUI

enum ReaderPanel: String, Identifiable {
    case toc
    case bookmarks
    case highlights
    case search
    case settings
    case flow
    case note

    var id: Self { self }

    var anchor: Self { self == .note ? .highlights : self }

    var title: String {
        switch self {
        case .toc: return "目录"
        case .bookmarks: return "书签"
        case .highlights: return "高亮标记和笔记"
        case .search: return "搜索"
        case .settings: return "主题与设置"
        case .flow: return "浏览模式"
        case .note: return "添加笔记"
        }
    }

    var width: CGFloat {
        switch self {
        case .highlights, .note: return 320
        case .settings, .flow: return 306
        default: return 286
        }
    }

    var contentHeight: CGFloat? {
        switch self {
        case .toc: return 480
        case .bookmarks: return 240
        case .highlights: return 400
        case .search: return 180
        case .settings, .flow, .note: return nil
        }
    }
}

struct ReaderPopoverContent<Content: View>: View {
    let panel: ReaderPanel
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Text(panel.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            Divider()
                .padding(.horizontal, 14)
            content()
                .frame(height: panel.contentHeight)
        }
        .frame(width: panel.width)
        .foregroundStyle(.primary)
    }
}
