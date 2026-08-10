import AppKit
import SwiftUI

/// Menu-bar-only app: accessory activation policy (no Dock icon), a lock
/// status item, and the popover panel as a MenuBarExtra window.
@main
struct UnlatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(systemName: hasLockedWork ? "lock" : "lock.open")
        }
        .menuBarExtraStyle(.window)
    }

    /// Closed lock while an encrypted file is loaded and not yet unlocked.
    private var hasLockedWork: Bool {
        model.files.contains { $0.kind == .encrypted && !$0.unlocked }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
