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
    /// A scheduled check found an update that Sparkle is holding without a window, and the user
    /// hasn't looked at it yet. Drives the footer indicator and the dot on the menu bar icon.
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

    /// Assigns the three stored values and never creates a Sparkle object.
    /// Only the debug-only preview factory below uses it.
    private init(
        availability: UpdaterAvailability, shortVersion: String?,
        canCheck: Bool, updateAvailable: Bool
    ) {
        self.availability = availability
        self.shortVersion = shortVersion
        self.canCheckForUpdates = canCheck
        self.updateAvailable = updateAvailable
        super.init()
    }

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

    /// Required for a dockless app. Sparkle logs a warning without it.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle never shows a scheduled update by itself: it keeps the alert unshown and the
    /// session open, and the in-app indicator is the reminder. `checkForUpdates()` then brings
    /// the held alert to the front. See Design/sparkle-updates.md §2.4.1.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        sparkleShowsScheduledUpdate(inImmediateFocus: immediateFocus)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        updateAvailable = updateIndicatorShown(
            after: .willShowUpdate(
                handledBySparkle: handleShowingUpdate, userInitiated: state.userInitiated),
            current: updateAvailable)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = updateIndicatorShown(after: .userAttention, current: updateAvailable)
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = updateIndicatorShown(after: .sessionFinished, current: updateAvailable)
    }
}

#if DEBUG
extension AppUpdater {
    /// Snapshot tests only. A footer that shows the "Update Available" button, with no
    /// Sparkle object behind it: `checkForUpdates()` does nothing because `controller` is nil.
    /// Compiled out of release builds (`Scripts/package-app.sh` builds `-c release`).
    static func previewingUpdateAvailable() -> AppUpdater {
        AppUpdater(
            availability: .enabled, shortVersion: nil, canCheck: true, updateAvailable: true)
    }
}
#endif
