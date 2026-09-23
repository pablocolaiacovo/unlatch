import AppKit

/// Menu-bar-only app: accessory activation policy (no Dock icon), with the
/// status item and popover owned entirely by AppKit (`StatusItemController`).
///
/// This is a plain AppKit entry point — `@main` directly on the delegate,
/// `NSApplication.shared.run()` — not a SwiftUI `App`. An earlier version
/// used `App` with a single `Settings { EmptyView() }` scene, kept only to
/// get the standard Edit menu for ⌘V/⌘C/⌘X/⌘A/⌘Z in the password field. On
/// macOS 27, activating the app with no visible window
/// (`NSApp.activate(ignoringOtherApps:)`, called from
/// `StatusItemController.presentAndFocus()` every time the popover opens)
/// made AppKit open that `Settings` scene as an empty, large "Unlatch
/// Settings" window behind the popover. With no SwiftUI scene at all, there
/// is nothing left to open by accident, so this removes the bug at its root
/// instead of trying to suppress a window SwiftUI decided to show. The main
/// menu below is hand-built to keep the same key equivalents. See
/// Design/status-item-popover.md §2.2 for the full reasoning.
@MainActor
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItemController: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = makeMainMenu()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(model: model)
    }

    /// A minimal main menu: an app menu with Quit, and a standard Edit menu
    /// so Undo, Redo, Cut, Copy, Paste, and Select All — with their usual
    /// key equivalents — reach the password field's text editor through
    /// AppKit's normal first-responder action routing. Every item's target
    /// is left `nil` (the default) so it dispatches to whatever view is
    /// first responder, exactly like Interface Builder's First Responder
    /// actions.
    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Quit Unlatch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        // undo:/redo: are the informal NSResponder/NSUndoManager selectors
        // Interface Builder wires the Edit menu to by convention; they are
        // not declared on a public Swift protocol, hence the string form.
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return mainMenu
    }
}
