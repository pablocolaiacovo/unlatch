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
    /// One instance for the process lifetime. It exists before
    /// applicationDidFinishLaunching because on a cold launch AppKit can call
    /// application(_:open:) first; the hand-off buffers until `connect(to:)`.
    private let finderHandoff = FinderHandoff()
    /// Assigned once at launch and never cleared: it owns Sparkle's controller,
    /// which nothing else retains.
    private var updater: AppUpdater?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = makeMainMenu()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let info = Bundle.main.infoDictionary
        let updater = AppUpdater(
            availability: updaterAvailability(
                bundleURL: Bundle.main.bundleURL,
                feedURL: info?["SUFeedURL"] as? String,
                publicEDKey: info?["SUPublicEDKey"] as? String),
            shortVersion: info?["CFBundleShortVersionString"] as? String)
        self.updater = updater
        statusItemController = StatusItemController(model: model, updater: updater)
        // After StatusItemController, whose init sets model.onLoad.
        NSApp.servicesProvider = finderHandoff
        model.onPanelConfirmed = { [finderHandoff] in finderHandoff.discardPending() }
        finderHandoff.connect { [model] urls in model.openFromOutside(urls) }
    }

    /// Open With > Unlatch, `open -a Unlatch file.pdf`, or a drop on the app
    /// icon. On a cold launch this runs before applicationDidFinishLaunching,
    /// so the files wait in the hand-off's buffer.
    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("Unlatch: hand-off received %d file(s) via %@", urls.count, "open")
        finderHandoff.receive(urls)
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
            withTitle: String(localized: Strings.quitUnlatch),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: String(localized: Strings.editMenu))
        editMenuItem.submenu = editMenu
        // undo:/redo: are the informal NSResponder/NSUndoManager selectors
        // Interface Builder wires the Edit menu to by convention; they are
        // not declared on a public Swift protocol, hence the string form.
        editMenu.addItem(withTitle: String(localized: Strings.undo), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: Strings.redo), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: Strings.cut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: Strings.copy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: Strings.paste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: String(localized: Strings.selectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        return mainMenu
    }
}
