import SwiftUI

@main
struct CodexWakeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Codex Wake") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Find") {
                    NotificationCenter.default.post(name: .codexWakeFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Clear Search") {
                    model.clearSearch()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(model.searchText.isEmpty)
            }
        }
    }
}

extension Notification.Name {
    static let codexWakeFocusSearch = Notification.Name("codexWakeFocusSearch")
    static let codexWakeNavigateThread = Notification.Name("codexWakeNavigateThread")
    static let codexWakeScrollDetail = Notification.Name("codexWakeScrollDetail")
}
