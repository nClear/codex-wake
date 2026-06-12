import SwiftUI

@main
struct CodexWakeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Codex Keeper") {
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
            }
        }
    }
}
