import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("CLEAN", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 540, idealWidth: 580, minHeight: 680, idealHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 580, height: 720)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
