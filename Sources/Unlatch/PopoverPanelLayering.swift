import AppKit

/// Moves the popover's window below a modal `NSOpenPanel` while one is open.
///
/// A status item's popover window sits at level 25, above the level 8 that
/// `runModal()` gives the panel. `runModal()` resets the panel's level even if
/// it is set first, so the only way to get the panel in front is to lower the
/// popover. `.floating` keeps the popover above other apps' normal windows,
/// where it stays visible behind the panel.
@MainActor
final class PopoverPanelLayering {
    static let loweredLevel = NSWindow.Level.floating

    /// The window to put back, held directly because a popover that closes
    /// while the panel is open no longer reaches it through its view, and
    /// AppKit can reuse that window the next time the popover shows.
    private var lowered: (window: NSWindow, level: NSWindow.Level)?

    /// Safe to call again for a window already lowered, which is needed
    /// because showing a popover again resets its window's level. A different
    /// window puts the earlier one back first.
    func lower(_ window: NSWindow?) {
        guard let window else { return }
        if lowered?.window !== window {
            restore()
            lowered = (window, window.level)
        }
        window.level = Self.loweredLevel
    }

    func restore() {
        guard let lowered else { return }
        lowered.window.level = lowered.level
        self.lowered = nil
    }
}
