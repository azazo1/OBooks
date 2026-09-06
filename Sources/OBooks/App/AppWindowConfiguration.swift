import AppKit

enum AppWindowConfiguration {
    static let settingsWindowID = NSUserInterfaceItemIdentifier("com.obooks.settings")

    /// 阅读窗口首次打开时的内容尺寸, 也作为原生阅读视图的初始分页视口.
    static let readerWindowSize = NSSize(width: 1180, height: 760)

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

    /// 云同步设置窗保持在主窗口之上, 不和书库抢台前调度主窗口身份.
    static func applySettingsWindowBehavior(_ window: NSWindow) {
        window.identifier = settingsWindowID
        window.level = .floating
        window.animationBehavior = .utilityWindow
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.styleMask.remove(.resizable)
    }

    /// 保持窗口顶边不动, 只改内容高度.
    static func windowFrame(keepingTopOf window: NSWindow, contentHeight: CGFloat) -> NSRect {
        let content = window.contentRect(forFrameRect: window.frame)
        let height = max(1, contentHeight.rounded(.up))
        let newContent = NSRect(x: content.origin.x, y: content.maxY - height, width: content.width, height: height)
        return window.frameRect(forContentRect: newContent)
    }

    static func setContentHeight(_ height: CGFloat, in window: NSWindow) {
        let frame = windowFrame(keepingTopOf: window, contentHeight: height)
        guard abs(frame.height - window.frame.height) > 0.5 else { return }
        window.setFrame(frame, display: true)
    }

    static func visibleSettingsWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier == settingsWindowID && $0.isVisible }
    }

    static func belongsToSettingsSession(_ window: NSWindow) -> Bool {
        var current: NSWindow? = window
        while let candidate = current {
            if candidate.identifier == settingsWindowID { return true }
            current = candidate.sheetParent ?? candidate.parent
        }
        return false
    }

    /// 云同步开着时把焦点拉回设置窗或其子窗, 避免主窗口抢焦点.
    @discardableResult
    static func keepSettingsFocusedIfNeeded(for window: NSWindow) -> Bool {
        guard let settings = visibleSettingsWindow(), !belongsToSettingsSession(window) else { return false }
        settings.makeKeyAndOrderFront(nil)
        return true
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
