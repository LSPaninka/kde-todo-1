import AppKit
import SwiftUI

/// AppKit entry point — we use NSStatusItem directly so we have pixel-level
/// control over the menu-bar icon. The app is a pure menu-bar app
/// (LSUIElement = YES in Info.plist), no Dock icon, no main window.
@main
struct CategorizedToDoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = TaskStore.shared
        let settings = AppSettings.shared
        statusBar = StatusBarController(store: store, settings: settings)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu-bar app: never quit just because a settings window closed.
        return false
    }
}
