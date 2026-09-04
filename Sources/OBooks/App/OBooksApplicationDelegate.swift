import AppKit

final class OBooksApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windowObservations: [NSObjectProtocol] = []
    private var applicationObservation: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        observeWindowLifecycle()
        applicationObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.configureNormalWindows()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureNormalWindows()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observation in windowObservations {
            NotificationCenter.default.removeObserver(observation)
        }
        windowObservations.removeAll()
        if let applicationObservation {
            NotificationCenter.default.removeObserver(applicationObservation)
            self.applicationObservation = nil
        }
    }

    private func observeWindowLifecycle() {
        let notificationNames = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification
        ]
        windowObservations = notificationNames.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.configureWindow(from: notification)
            }
        }
    }

    private func configureNormalWindows() {
        for window in NSApp.windows where window.level == .normal {
            AppWindowConfiguration.applyPrimaryStageBehavior(window)
        }
    }

    private func configureWindow(from notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.level == .normal else {
            return
        }
        AppWindowConfiguration.applyPrimaryStageBehavior(window)
    }
}
