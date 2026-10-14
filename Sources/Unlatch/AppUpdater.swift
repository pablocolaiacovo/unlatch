import AppKit
import Observation
import Sparkle

/// Owns Sparkle's standard updater for the process lifetime. Created and
/// retained by `AppDelegate`. Sparkle holds its delegates weakly.
///
/// When `availability` is not `.enabled` (`swift run`, a bundle without a
/// feed or key) no Sparkle object is created, so nothing runs and no alert can
/// appear. See Design/sparkle-updates.md §2.4.1.
@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    let availability: UpdaterAvailability
    /// Mirrors `SPUUpdater.canCheckForUpdates` (KVO).
    private(set) var canCheckForUpdates = false
    /// A scheduled update alert is on screen and hasn't had the user's attention yet.
    private(set) var updateAvailable = false

    /// The footer's input: `updateButtonState(...)` over the three values above.
    var buttonState: UpdateButtonState {
        updateButtonState(
            availability: availability, canCheck: canCheckForUpdates,
            updateAvailable: updateAvailable)
    }

    /// Set by `StatusItemController`: close the popover before Sparkle shows a
    /// window, the same pattern as `AppModel.onLoad`.
    @ObservationIgnored var onWillPresent: (@MainActor () -> Void)?

    @ObservationIgnored private let shortVersion: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init(availability: UpdaterAvailability, shortVersion: String?) {
        self.availability = availability
        self.shortVersion = shortVersion
        super.init()
        guard availability == .enabled else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        // Sparkle mutates this property on the main thread. The handler copies
        // the Bool and never sends the SPUUpdater anywhere.
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates, options: [.initial, .new]
        ) { [weak self] _, change in
            let value = change.newValue ?? false
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = value
            }
        }
        controller.startUpdater()
    }

    /// Both footer entry points (the menu item and the "Update Available"
    /// button) call this. The popover has to close first: it floats above
    /// normal windows and would cover Sparkle's window.
    func checkForUpdates() {
        onWillPresent?()
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        allowedUpdateChannels(forVersion: shortVersion)
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Required for a dockless app; Sparkle still shows the scheduled-update
    /// window itself because `standardUserDriverShouldHandleShowingScheduledUpdate`
    /// is not implemented.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            updateAvailable = true
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
    }
}
