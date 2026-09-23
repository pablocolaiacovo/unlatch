import AppKit
import Observation

/// Owns the `NSStatusItem` and the `NSPopover` that hosts `PopoverView`.
/// Replaces the previous SwiftUI menu bar scene, which gave no control over
/// dismissal and no access to the underlying status item. There is exactly
/// one instance, created by `AppDelegate` and living for the whole process.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private lazy var dismissalMonitor = PopoverDismissalMonitor(
        isModalPanelOpen: { NSApp.modalWindow != nil },
        close: { [weak self] in self?.closePopover() }
    )
    private var mouseUpHighlightMonitor: Any?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        model.onLoad = { [weak self] in self?.presentAndFocus() }

        configureStatusItem()
        configurePopover()
        observeModel()
        installHighlightMonitor()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Unlatch"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseDown])
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = PopoverHostingController(model: model)
        popover.delegate = self
    }

    /// Button action, sent on `.leftMouseDown` like a native menu extra.
    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            presentAndFocus()
        }
    }

    /// Shows the popover if hidden, then activates the app and makes the
    /// popover key. Idempotent, so it is safe to call unconditionally from a
    /// status item click or `AppModel.onLoad`.
    func presentAndFocus() {
        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        focusPopover()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    // MARK: NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        dismissalMonitor.start()
        updateHighlight()
    }

    func popoverDidClose(_ notification: Notification) {
        dismissalMonitor.stop()
        updateHighlight()
    }

    // MARK: Keyboard focus

    /// Under `.accessory`, a status item's popover isn't key unless the app
    /// is active. `activate(ignoringOtherApps:)` rather than the cooperative
    /// `activate()`: right after a drop from Finder, Finder is still active
    /// and has not yielded, so the cooperative call can be refused and the
    /// password field would be unreachable by keyboard.
    private func focusPopover() {
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Icon

    private func updateHighlight() {
        statusItem.button?.highlight(popover.isShown)
    }

    /// `sendAction(on: [.leftMouseDown])` fires `togglePopover` — and thus
    /// `updateHighlight()` — on mouse-down, before the button's own
    /// mouseDown/mouseUp tracking loop (which drives its native pressed
    /// look) has finished. That loop can un-highlight the button on
    /// mouse-up afterwards, undoing our call. A local monitor reasserts the
    /// highlight after every left mouse-up, deferred one main-actor turn so
    /// it lands after AppKit's own tracking has settled — this covers both
    /// a quick click and a slow press, since it fires exactly when the
    /// button is released rather than on a fixed delay.
    private func installHighlightMonitor() {
        mouseUpHighlightMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            MainActor.assumeIsolated {
                self?.reassertHighlightAfterTracking()
            }
            return event
        }
    }

    private func reassertHighlightAfterTracking() {
        Task { @MainActor [weak self] in
            self?.updateHighlight()
        }
    }

    /// `withObservationTracking` is one-shot, so it's re-armed from
    /// `onChange`, which fires in `willSet` and hops back to the main actor
    /// to read the new value on the next turn.
    private func observeModel() {
        withObservationTracking {
            renderButton(hasLockedWork: model.hasLockedWork)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModel() }
        }
    }

    private func renderButton(hasLockedWork: Bool) {
        let symbolName = statusSymbolName(hasLockedWork: hasLockedWork)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Unlatch")
        image?.isTemplate = true
        statusItem.button?.image = image
    }
}
