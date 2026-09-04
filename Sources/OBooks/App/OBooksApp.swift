import SwiftUI

@main
struct OBooksApp: App {
    @NSApplicationDelegateAdaptor(OBooksApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appModel = AppModel()

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
            CommandMenu("阅读") {
                Button("打开选中书籍") {
                    appModel.openSelectedBook()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}
