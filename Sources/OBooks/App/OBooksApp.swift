import SwiftUI

@main
struct OBooksApp: App {
    @NSApplicationDelegateAdaptor(OBooksApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appModel = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("OBooks") {
            LibraryView()
                .environmentObject(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入 EPUB") {
                    appModel.importEPUB()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(replacing: .appInfo) {
                Button("关于 OBooks") {
                    openWindow(id: "about")
                }
            }
            CommandMenu("阅读") {
                Button("打开选中书籍") {
                    appModel.openSelectedBook()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
            CommandGroup(after: .textEditing) {
                Button("搜索") {
                    NotificationCenter.default.post(
                        name: .obooksSearchRequested,
                        object: NSApp.keyWindow
                    )
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Window("关于 OBooks", id: "about") {
            AppAboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
