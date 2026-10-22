import Foundation
import PDFKit
import UnlatchCore

// Pure app logic, kept off the main actor and free of UI types so it can be
// unit-tested directly. The view model calls into these functions.

/// The file kinds the popover distinguishes, mapped from `Classification`.
/// `.notEncrypted` (`plain`) and `.ownerRestricted` (`owner`) are both usable
/// files with no open password, and both are copied to the destination
/// byte-for-byte (see `saveJobs`). They stay separate kinds only so the row
/// note can say which one it is: a plain file has no permissions to speak of.
enum FileKind: Equatable, Sendable {
    case encrypted, owner, plain, corrupt

    init(_ classification: Classification) {
        switch classification {
        case .userLocked: self = .encrypted
        case .ownerRestricted: self = .owner
        case .notEncrypted: self = .plain
        case .unreadable: self = .corrupt
        }
    }
}

/// The popover's state machine steps, exactly as in the design script.
enum Step: Equatable, Sendable {
    case idle, password, working, destination, done
}

/// Where the unlocked output goes; mirrors the design's four radio options.
enum DestinationOption: CaseIterable, Equatable, Sendable {
    case suffix, replace, desktop, other

    var label: LocalizedStringResource {
        switch self {
        case .suffix:
            LocalizedStringResource(
                "Same folder, add “-unlocked”", bundle: .unlatch,
                comment: "Destination radio option. Saves next to the original with a suffix. “-unlocked” is the literal text added to the file name and is not translated.")
        case .replace:
            LocalizedStringResource(
                "Same folder, replace original", bundle: .unlatch,
                comment: "Destination radio option. Overwrites the original file with the unlocked copy.")
        case .desktop:
            LocalizedStringResource(
                "Desktop", bundle: .unlatch,
                comment: "Destination radio option. Saves to the Desktop folder.")
        case .other:
            LocalizedStringResource(
                "Choose folder…", bundle: .unlatch,
                comment: "Destination radio option. Opens a panel to pick a folder.")
        }
    }
}

/// A loaded file plus its per-file outcome flags.
struct LoadedFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let kind: FileKind
    /// Encrypted file whose password did not match in a batch; it is skipped.
    var skipped = false
    /// Set once the file has been written to its destination.
    var unlocked = false
    /// Set when `save()` attempted this file and it did not write. Distinct
    /// from `skipped`, which means the file was never attempted at all.
    var failure: SaveFailure?

    init(url: URL, kind: FileKind) {
        self.id = UUID()
        self.url = url
        self.kind = kind
    }

    var name: String { url.lastPathComponent }
}

/// Why one file's save job didn't write, Sendable so it can cross the
/// detached task boundary that runs `executeSaveJob` — the thrown `Error`
/// itself is not. `.wrongPassword`, `.unreadable`, and `.writeFailed` mirror
/// `UnlockError`; `.copyFailed` is the fallback for the `FileManager` errors
/// a plain `copy` job can throw.
enum SaveFailure: Equatable, Sendable {
    case wrongPassword, unreadable, writeFailed, copyFailed

    init(_ error: UnlockError) {
        switch error {
        case .wrongPassword: self = .wrongPassword
        case .unreadable: self = .unreadable
        case .writeFailed: self = .writeFailed
        }
    }

    /// Short, human note for the file row — never a raw `localizedDescription`.
    var note: LocalizedStringResource {
        switch self {
        case .wrongPassword:
            LocalizedStringResource(
                "Password didn’t match — not saved", bundle: .unlatch,
                comment: "File row note. The shared password did not open this file, so it was not saved.")
        case .unreadable:
            LocalizedStringResource(
                "Couldn’t be read — not saved", bundle: .unlatch,
                comment: "File row note. The file could not be read, so it was not saved.")
        case .writeFailed:
            LocalizedStringResource(
                "Couldn’t write the file — not saved", bundle: .unlatch,
                comment: "File row note. Writing the unlocked copy failed, so nothing was saved for this file.")
        case .copyFailed:
            LocalizedStringResource(
                "Couldn’t be copied — not saved", bundle: .unlatch,
                comment: "File row note. Copying a file that needed no unlocking failed, so it was not saved.")
        }
    }
}

// MARK: - Step transitions

/// The step to enter after classifying a batch: any encrypted file demands a
/// password; otherwise any usable file goes straight to destination; a batch
/// of only corrupt files stays idle (their rows are still listed).
func step(afterLoading kinds: [FileKind]) -> Step {
    if kinds.contains(.encrypted) { return .password }
    if kinds.contains(where: { $0 != .corrupt }) { return .destination }
    return .idle
}

// MARK: - Destination URLs

/// Computes the output URL for one source file.
/// - suffix: `Name.pdf` → `Name-unlocked.pdf` next to the original
/// - replace: overwrite the original in place
/// - desktop / other: original filename inside the chosen folder
func destinationURL(
    for source: URL,
    option: DestinationOption,
    desktopFolder: URL,
    chosenFolder: URL?
) -> URL {
    switch option {
    case .suffix:
        let ext = source.pathExtension
        var url = source.deletingLastPathComponent()
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-unlocked")
        if !ext.isEmpty { url = url.appendingPathExtension(ext) }
        return url
    case .replace:
        return source
    case .desktop:
        return desktopFolder.appendingPathComponent(source.lastPathComponent)
    case .other:
        return (chosenFolder ?? desktopFolder).appendingPathComponent(source.lastPathComponent)
    }
}

// MARK: - Save jobs

/// What saving does to one file. Encrypted files go through `unlock`;
/// owner/plain files are copied byte-for-byte so "Copied as-is" stays true —
/// rewriting them through `unlock` would silently strip owner restrictions.
enum SaveAction: Equatable, Sendable {
    case unlock(password: String?)
    case copy
}

struct SaveJob: Equatable, Sendable {
    let source: URL
    let destination: URL
    let action: SaveAction
}

/// Builds the batch of save jobs. `password` must be the exact string the
/// password step verified — no trimming or other normalization — so that
/// verification and saving can never disagree about the password.
func saveJobs(
    for files: [LoadedFile],
    option: DestinationOption,
    desktopFolder: URL,
    chosenFolder: URL?,
    password: String?
) -> [SaveJob] {
    files.compactMap { file in
        guard file.kind != .corrupt, !file.skipped else { return nil }
        let destination = destinationURL(
            for: file.url, option: option,
            desktopFolder: desktopFolder, chosenFolder: chosenFolder)
        return SaveJob(
            source: file.url,
            destination: destination,
            action: file.kind == .encrypted ? .unlock(password: password) : .copy)
    }
}

/// Executes one job (blocking; call off the main actor). Copies go through a
/// temp file and an atomic replace, mirroring `unlock`'s write path; copying
/// a file onto itself (the "replace original" option) is a no-op success.
func executeSaveJob(_ job: SaveJob) throws {
    switch job.action {
    case .unlock(let password):
        try unlock(job.source, password: password, destination: job.destination)
    case .copy:
        guard job.source.standardizedFileURL != job.destination.standardizedFileURL else {
            return
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try FileManager.default.copyItem(at: job.source, to: temp)
        _ = try FileManager.default.replaceItemAt(job.destination, withItemAt: temp)
    }
}

// MARK: - Display strings

func abbreviatedPath(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}

/// Header right side: "Remove PDF passwords" with no files, else a count.
func headerNote(fileCount: Int) -> LocalizedStringResource {
    guard fileCount > 0 else {
        return LocalizedStringResource(
            "Remove PDF passwords", bundle: .unlatch,
            comment: "Header, right side, when no files are loaded: what the app does.")
    }
    return LocalizedStringResource(
        "\(fileCount) files", bundle: .unlatch,
        comment: "Header, right side: how many files are loaded. The value is a number, and 1 needs the singular.")
}

func passwordTitle(encryptedCount: Int) -> LocalizedStringResource {
    guard encryptedCount > 1 else {
        return LocalizedStringResource(
            "This PDF needs a password", bundle: .unlatch,
            comment: "Password step title when a single file is password protected.")
    }
    return LocalizedStringResource(
        "\(encryptedCount) files need a password", bundle: .unlatch,
        comment: "Password step title when several files are password protected. The value is always 2 or more.")
}

func passwordSubtitle(encrypted: [LoadedFile]) -> LocalizedStringResource {
    if encrypted.count > 1 {
        return LocalizedStringResource(
            "We’ll try the same password on all of them. Anything that doesn’t match gets skipped.",
            bundle: .unlatch,
            comment: "Password step subtitle when several files are protected: one password is tried on all of them.")
    }
    return verbatim(encrypted.first?.name ?? "")
}

/// Zero saved files is the failure state: nothing was written, so the step
/// must not read as a success. `failedCount` makes a partial batch honest
/// instead of only reporting the successes.
func doneTitle(savedCount: Int, failedCount: Int = 0) -> LocalizedStringResource {
    guard failedCount > 0 else {
        if savedCount == 0 {
            return LocalizedStringResource(
                "Couldn’t save — nothing was written", bundle: .unlatch,
                comment: "Done step title when no file could be saved.")
        }
        return savedCount > 1
            ? LocalizedStringResource(
                "\(savedCount) files saved", bundle: .unlatch,
                comment: "Done step title when several files were saved. The value is always 2 or more.")
            : LocalizedStringResource(
                "Saved", bundle: .unlatch,
                comment: "Done step title when one file was saved.")
    }
    if savedCount == 0 {
        return failedCount > 1
            ? LocalizedStringResource(
                "Couldn’t save — all \(failedCount) files failed", bundle: .unlatch,
                comment: "Done step title when every file of a batch failed. The value is always 2 or more.")
            : LocalizedStringResource(
                "Couldn’t save — the file failed", bundle: .unlatch,
                comment: "Done step title when the single file failed to save.")
    }
    return LocalizedStringResource(
        "\(savedCount) saved, \(failedCount) failed", bundle: .unlatch,
        comment: "Done step title for a partial batch: how many files were saved, then how many failed. Either value can be 1, so each needs its own singular and plural form.")
}

/// The monospaced "where it went" line on the done step. A single file shows
/// its full path; a batch in one folder summarizes that folder the way the
/// design does; a batch spanning folders states the spread truthfully. `nil`
/// when nothing was saved.
func doneSummary(destinations: [URL], option: DestinationOption) -> LocalizedStringResource? {
    guard let first = destinations.first else { return nil }
    if destinations.count == 1 { return verbatim(abbreviatedPath(first)) }

    let folders = Set(destinations.map { $0.deletingLastPathComponent().standardizedFileURL.path })
    guard folders.count == 1 else {
        return LocalizedStringResource(
            "\(destinations.count) files in \(folders.count) folders", bundle: .unlatch,
            comment: "Done step summary for a batch saved into several folders: file count, then folder count. Both values are always 2 or more.")
    }

    let dir = abbreviatedPath(first.deletingLastPathComponent())
    switch option {
    case .suffix:
        // The real file name pattern the app writes, so it is not translated.
        return verbatim(dir + "/…-unlocked.pdf")
    case .replace:
        return LocalizedStringResource(
            "\(dir)/ (originals replaced)", bundle: .unlatch,
            comment: "Done step summary when a batch overwrote its originals. The value is a folder path followed by a slash; move it if the language needs.")
    case .desktop, .other:
        return verbatim(dir + "/")
    }
}

/// The monospaced hint under each destination radio option, computed from the
/// first usable file so the paths are real rather than the design's samples.
func destinationHint(
    option: DestinationOption,
    sample: URL?,
    desktopFolder: URL,
    chosenFolder: URL?
) -> LocalizedStringResource {
    switch option {
    case .suffix:
        guard let sample else {
            return LocalizedStringResource(
                "next to the original", bundle: .unlatch,
                comment: "Hint under the “Same folder, add -unlocked” option before a sample path is known.")
        }
        return verbatim(abbreviatedPath(destinationURL(
            for: sample, option: .suffix, desktopFolder: desktopFolder, chosenFolder: nil)))
    case .replace:
        guard let sample else {
            return LocalizedStringResource(
                "overwrites the original", bundle: .unlatch,
                comment: "Hint under the “Same folder, replace original” option before a sample path is known.")
        }
        return verbatim(abbreviatedPath(sample))
    case .desktop:
        return verbatim(abbreviatedPath(desktopFolder) + "/")
    case .other:
        guard let chosenFolder else {
            return LocalizedStringResource(
                "opens a save panel", bundle: .unlatch,
                comment: "Hint under the “Choose folder…” option before a folder has been chosen.")
        }
        return verbatim(abbreviatedPath(chosenFolder) + "/")
    }
}

/// Footer left side: "Version 1.0.0 (42)". Takes the raw Info.plist values
/// (`CFBundleShortVersionString`, `CFBundleVersion`) and passes them through
/// untouched, so `git describe` forms like `1.0.0-3-gabc1234-dirty` survive.
/// Missing or empty values (no Info.plist under `swift run`) read as "dev".
func versionLabel(version: String?, build: String?) -> LocalizedStringResource {
    let version = version.flatMap { $0.isEmpty ? nil : $0 } ?? "dev"
    let build = build.flatMap { $0.isEmpty ? nil : $0 }
    guard let build else {
        return LocalizedStringResource(
            "Version \(version)", bundle: .unlatch,
            comment: "Disabled menu item showing the app version, for example “Version 1.2.0”. The value is a version number, or “dev” in a development build.")
    }
    return LocalizedStringResource(
        "Version \(version) (\(build))", bundle: .unlatch,
        comment: "Disabled menu item showing the app version and build number, for example “Version 1.2.0 (42)”.")
}

/// The destination step's question. The count is not shown, so the code picks
/// the key and each language words the singular and plural sentences itself.
func destinationQuestion(usableCount: Int) -> LocalizedStringResource {
    usableCount > 1
        ? LocalizedStringResource(
            "Where should the unlocked files go?", bundle: .unlatch,
            comment: "Destination step title when several files will be saved.")
        : LocalizedStringResource(
            "Where should the unlocked file go?", bundle: .unlatch,
            comment: "Destination step title when one file will be saved.")
}

// MARK: - File rows

/// Semantic badge tone; the view maps tones to the design's exact colors.
enum RowTone: Equatable, Sendable {
    case neutral, success, warning, error
}

struct RowInfo: Equatable, Sendable {
    let badge: String
    let tone: RowTone
    let note: LocalizedStringResource
}

/// Badge and note for one file row, matching the design's `buildRows`.
/// An encrypted file whose password didn't match keeps its pending look —
/// it was skipped, not unlocked. A file that was attempted and failed to
/// write gets its own error badge, distinct from both "Unlocked" and the
/// pending "Password protected" look.
func rowInfo(for file: LoadedFile, done: Bool) -> RowInfo {
    if done, let failure = file.failure {
        return RowInfo(badge: "!", tone: .error, note: failure.note)
    }
    switch file.kind {
    case .corrupt:
        return RowInfo(badge: "!", tone: .error, note: LocalizedStringResource(
                "Not a readable PDF — skipped", bundle: .unlatch,
                comment: "File row note. The file is not a PDF the app can read, so it is skipped."))
    case .owner:
        return RowInfo(
            badge: "i", tone: .warning,
            note: done && file.unlocked
                ? LocalizedStringResource(
                    "Copied as-is — opens without a password", bundle: .unlatch,
                    comment: "File row note after saving a PDF that only had permission restrictions: it was copied unchanged and already opens without a password.")
                : LocalizedStringResource(
                    "No open password — permissions only", bundle: .unlatch,
                    comment: "File row note. The PDF opens without a password and only restricts permissions such as printing or copying."))
    case .plain:
        return RowInfo(
            badge: "i", tone: .neutral,
            note: done && file.unlocked
                ? LocalizedStringResource(
                    "Not encrypted — copied as-is", bundle: .unlatch,
                    comment: "File row note after saving a PDF that had no protection: it was copied unchanged.")
                : LocalizedStringResource(
                    "Not encrypted — nothing to unlock", bundle: .unlatch,
                    comment: "File row note. The PDF has no protection at all, so there is nothing to unlock."))
    case .encrypted:
        if done && file.unlocked {
            return RowInfo(badge: "✓", tone: .success, note: LocalizedStringResource(
                    "Unlocked", bundle: .unlatch,
                    comment: "File row note after the password was removed and the file saved."))
        }
        return RowInfo(badge: "•", tone: .neutral, note: LocalizedStringResource(
                "Password protected", bundle: .unlatch,
                comment: "File row note. The PDF needs a password to open."))
    }
}

// MARK: - Status item

/// Closed lock while any loaded file is still encrypted and not yet
/// unlocked. Drives the status item glyph in `StatusItemController`.
func hasLockedWork(_ files: [LoadedFile]) -> Bool {
    files.contains { $0.kind == .encrypted && !$0.unlocked }
}

/// SF Symbol name for the status item button.
func statusSymbolName(hasLockedWork: Bool) -> String {
    hasLockedWork ? "lock" : "lock.open"
}

/// What the menu bar status item shows (Design/sparkle-updates.md §2.4.3).
struct StatusItemPresentation: Equatable, Sendable {
    /// `statusSymbolName(hasLockedWork:)`: "lock" or "lock.open".
    let symbolName: String
    /// The dot on the icon. Same condition as the footer's indicator.
    let showsUpdateBadge: Bool
    /// `nil`, or `updateAvailableValue`.
    let accessibilityValue: LocalizedStringResource?
    let toolTip: LocalizedStringResource

    /// The app name: a `String`, never translated.
    static let accessibilityLabel = "Unlatch"
    static let updateAvailableValue = LocalizedStringResource(
        "Update available", bundle: .unlatch,
        comment: "Accessibility value of the menu bar icon and the More button when a new version is available.")
    static let updateAvailableToolTip = LocalizedStringResource(
        "Unlatch: update available", bundle: .unlatch,
        comment: "Tooltip of the menu bar icon when a new version is available. “Unlatch” is the app name.")
}

/// `showsUpdateBadge` is `updateFooterPresentation(for: updateState).showsUpdateIndicator`, so the
/// icon and the footer can't disagree. With the badge: `updateAvailableValue` and
/// `updateAvailableToolTip`. Without: no value and "Unlatch".
func statusItemPresentation(
    hasLockedWork: Bool, updateState: UpdateButtonState
) -> StatusItemPresentation {
    let badge = updateFooterPresentation(for: updateState).showsUpdateIndicator
    return StatusItemPresentation(
        symbolName: statusSymbolName(hasLockedWork: hasLockedWork),
        showsUpdateBadge: badge,
        accessibilityValue: badge ? StatusItemPresentation.updateAvailableValue : nil,
        toolTip: badge
            ? StatusItemPresentation.updateAvailableToolTip
            : verbatim(StatusItemPresentation.accessibilityLabel))
}

// MARK: - Launch at Login

/// The login item's state as the system reports it, folded down from
/// `SMAppService.Status` (see `LoginItem.swift`) so the mapping to the UI is
/// testable without ServiceManagement.
enum LoginItemStatus: Equatable, Sendable {
    /// Registered and allowed: Unlatch opens at login.
    case enabled
    /// Not registered, including a bundle that has never been registered
    /// (`SMAppService.Status.notFound`). Checking the box registers it.
    case disabled
    /// Registered, but switched off in System Settings > General > Login
    /// Items. Unlatch does not open at login, and only the user can allow it
    /// again from there.
    case requiresApproval
    /// No login item is possible: no bundle identifier (e.g. `swift run`), or
    /// a status this build does not know.
    case unavailable
}

/// What the footer's "Open at Login" menu item shows. `isOn` follows the
/// system state, never a stored preference, so the menu item cannot claim
/// Unlatch opens at login when System Settings says otherwise.
struct LoginItemControl: Equatable, Sendable {
    let isOn: Bool
    let isEnabled: Bool
    let help: LocalizedStringResource
}

func loginItemControl(for status: LoginItemStatus) -> LoginItemControl {
    switch status {
    case .enabled:
        LoginItemControl(isOn: true, isEnabled: true, help: LocalizedStringResource(
                "Unlatch opens when you log in", bundle: .unlatch,
                comment: "Tooltip of the Open at Login menu item when it is on."))
    case .disabled:
        LoginItemControl(isOn: false, isEnabled: true, help: LocalizedStringResource(
                "Open Unlatch when you log in", bundle: .unlatch,
                comment: "Tooltip of the Open at Login menu item when it is off."))
    case .requiresApproval:
        LoginItemControl(
            isOn: false, isEnabled: true,
            help: LocalizedStringResource(
                "Turned off in System Settings > General > Login Items. Check to open Login Items and allow Unlatch.",
                bundle: .unlatch,
                comment: "Tooltip of the Open at Login menu item when the user switched Unlatch off in the macOS login items settings. Do not name the System Settings pane in translations: it has different names across Spanish-speaking regions."))
    case .unavailable:
        LoginItemControl(
            isOn: false, isEnabled: false,
            help: LocalizedStringResource(
                "Available when Unlatch runs from an app bundle", bundle: .unlatch,
                comment: "Tooltip of the disabled Open at Login menu item when the app runs outside an app bundle, for example during development."))
    }
}

/// What choosing the menu item does from a given status.
enum LoginItemAction: Equatable, Sendable {
    case register, unregister, openSystemSettings, noChange
}

/// A login item the user switched off in System Settings cannot be switched
/// back on by the app; `register()` leaves it waiting for approval. So
/// checking the box in that state opens Login Items instead. Unchecking it
/// unregisters, which clears the pending entry.
func loginItemAction(from status: LoginItemStatus, turningOn: Bool) -> LoginItemAction {
    switch (status, turningOn) {
    case (.disabled, true): .register
    case (.requiresApproval, true): .openSystemSettings
    case (.enabled, false), (.requiresApproval, false): .unregister
    case (.enabled, true), (.disabled, false), (.unavailable, _): .noChange
    }
}

// MARK: - Updates (Sparkle)

/// Whether this process can run Sparkle at all.
enum UpdaterAvailability: Equatable, Sendable {
    case enabled
    case disabled(UpdaterDisabledReason)
}

enum UpdaterDisabledReason: Equatable, Sendable {
    /// `swift run`, the test runner: Bundle.main is not an .app, so there is
    /// no Info.plist and Sparkle would fail to start ("does not have a valid
    /// bundle identifier") and show an error alert on every launch.
    case notAnAppBundle
    case missingFeedURL
    /// Anything other than an https URL.
    case insecureFeedURL
    case missingPublicKey
}

/// Checks run in order. Empty strings count as missing.
func updaterAvailability(
    bundleURL: URL, feedURL: String?, publicEDKey: String?
) -> UpdaterAvailability {
    guard bundleURL.pathExtension == "app" else { return .disabled(.notAnAppBundle) }
    guard let feedURL, !feedURL.isEmpty else { return .disabled(.missingFeedURL) }
    guard let url = URL(string: feedURL), url.scheme?.lowercased() == "https",
        url.host?.isEmpty == false
    else { return .disabled(.insecureFeedURL) }
    guard let publicEDKey, !publicEDKey.isEmpty else { return .disabled(.missingPublicKey) }
    return .enabled
}

/// `["beta"]` when the running build is itself a beta (its
/// CFBundleShortVersionString contains "-beta.", including `git describe`
/// forms such as "1.1.0-beta.2-3-gabc1234"). Otherwise `[]`, meaning the
/// default channel only. Sparkle always includes the default channel, so
/// beta builds see stable releases too.
func allowedUpdateChannels(forVersion shortVersion: String?) -> Set<String> {
    guard let shortVersion, shortVersion.contains("-beta.") else { return [] }
    return ["beta"]
}

enum UpdateButtonState: Equatable, Sendable {
    case hidden, checkDisabled, check, updateAvailable
}

/// `.hidden` unless availability is `.enabled`. With `canCheck` false, the
/// result is `.checkDisabled`, even when `updateAvailable` is true. Otherwise
/// `updateAvailable` selects `.updateAvailable` and anything else gives `.check`.
func updateButtonState(
    availability: UpdaterAvailability, canCheck: Bool, updateAvailable: Bool
) -> UpdateButtonState {
    guard availability == .enabled else { return .hidden }
    guard canCheck else { return .checkDisabled }
    return updateAvailable ? .updateAvailable : .check
}

/// What the popover footer shows for the updater (option C, #57).
struct UpdateFooterPresentation: Equatable, Sendable {
    /// The update item in the ellipsis menu. `nil` leaves it out of the menu.
    let menuItemTitle: LocalizedStringResource?
    let menuItemEnabled: Bool
    /// The accent "Update Available" footer button and the dot on the ellipsis button.
    let showsUpdateIndicator: Bool

    static let checkTitle = LocalizedStringResource(
        "Check for Updates…", bundle: .unlatch,
        comment: "Menu item that checks for a new version now.")
    /// Confirmed by the maintainer on 2026-10-14 (Design/sparkle-updates.md §6 question 5).
    static let updateAvailableTitle = LocalizedStringResource(
        "Update Available…", bundle: .unlatch,
        comment: "Menu item shown instead of “Check for Updates…” when a new version is available.")
}

/// `.hidden`: no item, no indicator. `.checkDisabled`: `checkTitle`, disabled, no indicator.
/// `.check`: `checkTitle`, enabled, no indicator. `.updateAvailable`: `updateAvailableTitle`,
/// enabled, indicator shown.
func updateFooterPresentation(for state: UpdateButtonState) -> UpdateFooterPresentation {
    switch state {
    case .hidden:
        UpdateFooterPresentation(
            menuItemTitle: nil, menuItemEnabled: false, showsUpdateIndicator: false)
    case .checkDisabled:
        UpdateFooterPresentation(
            menuItemTitle: UpdateFooterPresentation.checkTitle, menuItemEnabled: false,
            showsUpdateIndicator: false)
    case .check:
        UpdateFooterPresentation(
            menuItemTitle: UpdateFooterPresentation.checkTitle, menuItemEnabled: true,
            showsUpdateIndicator: false)
    case .updateAvailable:
        UpdateFooterPresentation(
            menuItemTitle: UpdateFooterPresentation.updateAvailableTitle, menuItemEnabled: true,
            showsUpdateIndicator: true)
    }
}

/// The "Check Automatically" item in the ellipsis menu (#71).
struct AutomaticChecksMenuItem: Equatable, Sendable {
    let title: LocalizedStringResource
    let isChecked: Bool

    static let checkAutomaticallyTitle = LocalizedStringResource(
        "Check Automatically", bundle: .unlatch,
        comment: "Checkable menu item: whether the app looks for new versions by itself.")
}

/// `nil` (the item is left out) unless availability is `.enabled`, matching how the update item
/// is hidden. Otherwise `checkAutomaticallyTitle`, checked when `isOn` is true. Always enabled:
/// the setting is independent of `canCheckForUpdates` and of an update session in progress.
func automaticChecksMenuItem(
    availability: UpdaterAvailability, isOn: Bool
) -> AutomaticChecksMenuItem? {
    guard availability == .enabled else { return nil }
    return AutomaticChecksMenuItem(
        title: AutomaticChecksMenuItem.checkAutomaticallyTitle, isChecked: isOn)
}

/// What Sparkle's standard user driver reports about the update on offer.
enum UpdateReminderEvent: Equatable, Sendable {
    /// `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)`
    case willShowUpdate(handledBySparkle: Bool, userInitiated: Bool)
    /// `standardUserDriverDidReceiveUserAttention(forUpdate:)`
    case userAttention
    /// `standardUserDriverWillFinishUpdateSession()`
    case sessionFinished
}

/// Maintainer decision 2026-10-15: Sparkle never shows a scheduled update by itself, not even in
/// immediate focus. The in-app indicator is the only reminder. Always false.
func sparkleShowsScheduledUpdate(inImmediateFocus immediateFocus: Bool) -> Bool {
    false
}

/// The next value of `AppUpdater.updateAvailable`. `.willShowUpdate` with `userInitiated` false
/// gives true, whatever `handledBySparkle` says. `.willShowUpdate` with `userInitiated` true keeps
/// `current` (Sparkle shows that update itself, in front). `.userAttention` and `.sessionFinished`
/// give false.
func updateIndicatorShown(after event: UpdateReminderEvent, current: Bool) -> Bool {
    switch event {
    case .willShowUpdate(_, let userInitiated):
        userInitiated ? current : true
    case .userAttention, .sessionFinished:
        false
    }
}

// MARK: - PDF helpers (blocking; call off the main actor)

/// True when `password` opens the document (or it needs no password at all).
func passwordWorks(_ password: String, for url: URL) -> Bool {
    guard let doc = PDFDocument(url: url) else { return false }
    if !doc.isLocked { return true }
    return doc.unlock(withPassword: password)
}
