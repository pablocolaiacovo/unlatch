import AppKit
import SwiftUI

/// Menu-bar-only app: accessory activation policy (no Dock icon), with the
/// status item and popover owned by AppKit (`StatusItemController`) instead
/// of the previous SwiftUI menu bar scene. `Settings` is a placeholder
/// scene — it opens no window at launch — kept only because a SwiftUI `App`
/// needs at least one scene to install the standard main menu. That menu's
/// Edit items are how ⌘V, ⌘C, ⌘X, and ⌘A reach the password field; its own
/// "Settings…" item is removed so it can't open an empty window.
@main
struct UnlatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(model: model)
    }
}
