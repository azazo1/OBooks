import SwiftUI

@main
struct OBooksApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("OBooks") {
            LibraryView()
                .environmentObject(appModel)
        }
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
