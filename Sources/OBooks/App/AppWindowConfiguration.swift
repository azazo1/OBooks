import AppKit

enum AppWindowConfiguration {
    /// 阅读窗口底色跟随系统外观, 避免标题栏在浅色主题下露出黑色.
    static func readerWindowBackgroundColor(isDark: Bool) -> NSColor {
        isDark ? .black : .windowBackgroundColor
    }

    static func readerWindowBackgroundColor(appearance: NSAppearance? = nil) -> NSColor {
        let match = (appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua])
        return readerWindowBackgroundColor(isDark: match == .darkAqua)
    }

    /// 把窗口标成台前调度的主窗口, 聚焦时点击桌面才能被收入一侧.
    static func applyPrimaryStageBehavior(_ window: NSWindow) {
        window.level = .normal
        window.animationBehavior = .documentWindow
        window.collectionBehavior = [.primary, .managed]
    }

    /// 按当前屏幕可见区域居中, 避免新窗口落在边角.
    static func centerOnScreen(_ window: NSWindow) {
        guard let screen = preferredScreen(for: window) else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.origin.x + ((visible.width - frame.width) / 2).rounded()
        frame.origin.y = visible.origin.y + ((visible.height - frame.height) / 2).rounded()
        window.setFrame(frame, display: true)
    }

    static func preferredScreen(for window: NSWindow) -> NSScreen? {
        NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
