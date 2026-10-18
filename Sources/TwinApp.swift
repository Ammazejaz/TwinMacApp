import AppKit
import SwiftUI

@main
struct TwinApp: App {
    @StateObject private var model = LauncherModel()

    var body: some Scene {
        WindowGroup("Twin") {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 940, height: 640)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Application…") { model.addApplication() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open Second Account") {
                    if let app = model.selectedApp { model.launchSecondAccount(app) }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.selectedApp?.profileSupport.isAvailable != true || model.busyID != nil)
            }
            CommandGroup(after: .appInfo) {
                Text("Twin 0.2 · Local prototype")
            }
        }
    }
}
