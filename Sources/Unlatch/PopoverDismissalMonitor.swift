import AppKit

/// Closes the popover on any interaction outside it, except while a modal
/// panel — the `NSOpenPanel` from `AppModel.browse()` or
/// `chooseOtherFolder()` — is running.
///
/// Every outside mouse-down, app resign-active, Escape key-down, or Space
/// change closes the popover immediately. This is v1.0's dismissal
/// behaviour, not an interim step: dragging a file in from Finder still
/// closes the popover before it reaches the in-popover drop zone, and a
/// spike found dropping onto the menu bar icon itself is not viable either
/// — Mission Control's drag-to-top-edge behaviour steals the drag every
/// time. v1.0 is picker-only; see Design/status-item-popover.md §5 for the
/// spike result and the maintainer's decision.
///
/// Escape is handled with a local `.keyDown` monitor rather than
/// `NSViewController.cancelOperation(_:)` on the hosting controller: AppKit
/// only routes Escape to `cancelOperation(_:)` when it reaches that
/// controller through the responder chain, which isn't guaranteed here — a
/// SwiftUI `SecureField`'s field editor can be first responder, and the idle
/// step has no focusable control at all. A local key monitor sees every
/// Escape key-down delivered to the app while installed, independent of
/// first responder, so it works on every step.
@MainActor
final class PopoverDismissalMonitor {
    private static let escapeKeyCode: UInt16 = 53

    private let isModalPanelOpen: @MainActor () -> Bool
    private let close: @MainActor () -> Void

    private var globalMouseDownMonitor: Any?
    private var escKeyMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?

    init(isModalPanelOpen: @escaping @MainActor () -> Bool, close: @escaping @MainActor () -> Void) {
        self.isModalPanelOpen = isModalPanelOpen
        self.close = close
    }

    /// Installs the monitors and observers. Call when the popover shows.
    /// Calls `stop()` first, so calling `start()` twice in a row (a double
    /// `popoverDidShow`) can't leak monitors.
    func start() {
        stop()

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // Mouse event monitor handlers run on the main thread but are not
            // @MainActor by signature.
            MainActor.assumeIsolated {
                self?.handleOutsideInteraction()
            }
        }

        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            // NSEvent isn't Sendable, so it can't be returned out of
            // assumeIsolated; decide with a Sendable Bool instead and apply
            // it to `event` out here.
            let shouldConsume = MainActor.assumeIsolated { () -> Bool in
                // Let a modal NSOpenPanel handle its own Escape-to-cancel
                // instead of swallowing the event out from under it.
                guard let self, !self.isModalPanelOpen() else { return false }
                self.close()
                return true
            }
            return shouldConsume ? nil : event
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleOutsideInteraction()
            }
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleOutsideInteraction()
            }
        }
    }

    /// Removes everything installed by `start()`. Call when the popover
    /// closes, so nothing fires while it is already hidden.
    func stop() {
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
        }
        globalMouseDownMonitor = nil

        if let escKeyMonitor {
            NSEvent.removeMonitor(escKeyMonitor)
        }
        escKeyMonitor = nil

        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
        resignActiveObserver = nil

        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        spaceChangeObserver = nil
    }

    private func handleOutsideInteraction() {
        guard !isModalPanelOpen() else { return }
        close()
    }
}
