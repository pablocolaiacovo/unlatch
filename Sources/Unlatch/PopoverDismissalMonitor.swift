import AppKit

/// Closes the popover on any interaction outside it, except while a modal
/// panel — the `NSOpenPanel` from `AppModel.browse()` or
/// `chooseOtherFolder()` — is running.
///
/// This is task 1's simple form: every outside mouse-down, app resign-active,
/// or Space change closes the popover immediately, matching today's
/// `MenuBarExtra` behaviour (the Finder drag bug is unchanged). A later task
/// swaps the body of `handleOutsideInteraction()` for a reducer that keeps
/// the popover open while a file drag reaches one of Unlatch's drop targets,
/// without changing this type's public API.
@MainActor
final class PopoverDismissalMonitor {
    private let isModalPanelOpen: @MainActor () -> Bool
    private let close: @MainActor () -> Void

    private var globalMouseDownMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?

    init(isModalPanelOpen: @escaping @MainActor () -> Bool, close: @escaping @MainActor () -> Void) {
        self.isModalPanelOpen = isModalPanelOpen
        self.close = close
    }

    /// Installs the monitors and observers. Call when the popover shows.
    func start() {
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // Mouse event monitor handlers run on the main thread but are not
            // @MainActor by signature.
            MainActor.assumeIsolated {
                self?.handleOutsideInteraction()
            }
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
