import AppKit

final class ReaderWindow: NSWindow {
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(NSWindow.performClose(_:)) else {
            return super.validateMenuItem(menuItem)
        }
        return withVisibleCloseButton {
            super.validateMenuItem(menuItem)
        }
    }

    override func performClose(_ sender: Any?) {
        withVisibleCloseButton {
            super.performClose(sender)
        }
    }

    private func withVisibleCloseButton<Result>(_ action: () -> Result) -> Result {
        guard let button = standardWindowButton(.closeButton) else { return action() }
        // AppKit 会拒绝关闭按钮透明的窗口, 同步恢复透明度以保留原生关闭校验和代理回调.
        let alpha = button.alphaValue
        button.alphaValue = 1
        defer { button.alphaValue = alpha }
        return action()
    }
}
