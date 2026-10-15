import AppKit
import Observation

/// Owns the `NSStatusItem` and the `NSPopover` that hosts `PopoverView`.
/// Replaces the previous SwiftUI menu bar scene, which gave no control over
/// dismissal and no access to the underlying status item. There is exactly
/// one instance, created by `AppDelegate` and living for the whole process.
/// While an update is available the icon carries a small dot (Design/sparkle-updates.md §2.4.3).
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let updater: AppUpdater
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private lazy var dismissalMonitor = PopoverDismissalMonitor(
        isModalPanelOpen: { NSApp.modalWindow != nil },
        close: { [weak self] in self?.closePopover() }
    )
    private var mouseUpHighlightMonitor: Any?

    init(model: AppModel, updater: AppUpdater) {
        self.model = model
        self.updater = updater
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        model.onLoad = { [weak self] in self?.presentAndFocus() }
        updater.onWillPresent = { [weak self] in self?.closePopover() }

        configureStatusItem()
        configurePopover()
        observeState()
        installHighlightMonitor()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseDown])
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = PopoverHostingController(model: model, updater: updater)
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
            model.refreshLoginItem()
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
    /// to read the new value on the next turn. Tracks both the model's lock
    /// state and the updater's button state.
    private func observeState() {
        withObservationTracking {
            render(statusItemPresentation(
                hasLockedWork: model.hasLockedWork, updateState: updater.buttonState))
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeState() }
        }
    }

    private func render(_ presentation: StatusItemPresentation) {
        // No image accessibilityDescription: the button's label already says "Unlatch", and
        // having both would make VoiceOver read it twice.
        guard let button = statusItem.button,
              let symbol = NSImage(systemSymbolName: presentation.symbolName,
                                   accessibilityDescription: nil)
        else { return }
        let image = presentation.showsUpdateBadge ? Self.badged(symbol) : symbol
        image.isTemplate = true
        button.image = image
        button.toolTip = presentation.toolTip
        button.setAccessibilityLabel(StatusItemPresentation.accessibilityLabel)
        button.setAccessibilityValue(presentation.accessibilityValue)
    }

    /// The symbol with a dot at its top-trailing corner, separated from the glyph by a transparent
    /// ring. Same size and alignment rect as the symbol, so the icon doesn't move when the dot
    /// comes and goes. Stays a template image: AppKit tints it for light, dark, and tinted menu
    /// bars and for the pressed highlight.
    /// `nonisolated`: AppKit may call an NSImage drawing handler on any thread, and the handler
    /// isn't `@Sendable`, so inside a main-actor method it would inherit main-actor isolation and
    /// log a data race at run time.
    nonisolated private static func badged(_ symbol: NSImage) -> NSImage {
        let diameter: CGFloat = 6, ring: CGFloat = 1.5
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter,
                             width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -ring, dy: -ring)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.alignmentRect = symbol.alignmentRect
        return image
    }
}
