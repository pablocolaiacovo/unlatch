import AppKit
import Observation
import UniformTypeIdentifiers
import UnlatchCore

/// UI state for the popover. All mutation happens on the main actor; file I/O
/// (classification, password checks, unlocking) runs in detached tasks that
/// only exchange Sendable values with the model.
@MainActor
@Observable
final class AppModel {
    var step: Step = .idle
    var files: [LoadedFile] = []

    var password = ""
    /// The exact string `passwordWorks` accepted at the password step. save()
    /// must pass this same string to `unlock` — never a re-read or normalized
    /// copy of `password` — so verify and save can never disagree.
    private(set) var verifiedPassword: String?
    var revealPassword = false
    var passwordError = false
    /// Incremented on each failed attempt to drive the shake animation.
    var shakeCount = 0

    /// Bumped on every load and reset. A classification, password check, or
    /// save that finishes under an older generation belongs to a batch that
    /// is gone, and its result is dropped.
    private var loadGeneration = 0

    var destination: DestinationOption = .suffix
    var chosenFolder: URL?

    var savedURLs: [URL] = []
    var savedTo: LocalizedStringResource?

    private let loginItemService: any LoginItemService
    /// Read from the system at launch and every time the popover opens,
    /// since the user can change it in System Settings at any time.
    private(set) var loginItemStatus: LoginItemStatus = .unavailable

    init(loginItemService: any LoginItemService = SystemLoginItem()) {
        self.loginItemService = loginItemService
        loginItemStatus = loginItemService.status
    }

    var desktopFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    // MARK: Derived state

    /// Closed lock while an encrypted file is loaded and not yet unlocked.
    /// Drives the `lock` / `lock.open` status item glyph.
    var hasLockedWork: Bool { Unlatch.hasLockedWork(files) }

    /// Set by `StatusItemController`. Called synchronously at the start of
    /// every accepted load (in-popover drop or browse) so the AppKit layer
    /// can show the popover and make it key before the step changes.
    @ObservationIgnored var onLoad: (@MainActor () -> Void)?

    /// True while browse() or chooseOtherFolder() runs its modal NSOpenPanel.
    /// No view reads it, so it is not observed; it stays settable (not
    /// private) because the tests set it to simulate an open panel.
    @ObservationIgnored var isPresentingPanel = false
    /// The newest request received while busy. Each hold replaces it rather
    /// than adding to it (newest wins). private(set) so tests can read it.
    @ObservationIgnored private(set) var heldExternalFiles = IncomingFiles()
    /// Called when the user confirms browse()'s or chooseOtherFolder()'s
    /// panel, so whatever the outside hand-off still buffers can't replace the
    /// user's pick.
    @ObservationIgnored var onPanelConfirmed: (@MainActor () -> Void)?

    var encryptedFiles: [LoadedFile] { files.filter { $0.kind == .encrypted } }
    var usableFiles: [LoadedFile] { files.filter { $0.kind != .corrupt && !$0.skipped } }
    /// Files `save()` attempted and that did not write, for the done step's title.
    var failedCount: Int { files.count { $0.failure != nil } }
    /// The persistent rows section shows whenever files are loaded, except
    /// while the spinner is up.
    var showsFileRows: Bool { !files.isEmpty && step != .working }
    var headerText: LocalizedStringResource { headerNote(fileCount: files.count) }
    /// Sample file for the destination hints: the first usable one.
    var sampleFile: URL? { usableFiles.first?.url }
    var loginItem: LoginItemControl { loginItemControl(for: loginItemStatus) }

    // MARK: Loading

    // StatusItemController's dismissal monitor ignores outside interactions
    // while an NSOpenPanel is modal (NSApp.modalWindow != nil), so opening
    // this panel no longer dismisses the popover. `.level = .modalPanel`
    // keeps the panel in front, and activating first raises it above other
    // apps too.
    func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        isPresentingPanel = true
        let response = panel.runModal()
        isPresentingPanel = false
        browsePanelClosed(urls: response == .OK ? panel.urls : nil)
    }

    /// What browse() does once its panel closes; `nil` means cancelled. A
    /// confirm discards files held from outside, a cancel loads them.
    func browsePanelClosed(urls: [URL]?) {
        guard let urls, !urls.isEmpty else {
            resumeExternalOpen()
            return
        }
        discardExternalFiles()
        load(urls)
    }

    /// Entry point for files from outside the app (Finder). Same effect as
    /// choosing them with browse(): replaces the current batch and opens the
    /// popover. Holds them instead while work is in flight; the newest hold
    /// replaces any older one.
    func openFromOutside(_ urls: [URL]) {
        var incoming = IncomingFiles()
        incoming.add(urls)
        guard !incoming.isEmpty else { return }
        switch externalOpenAction(step: step, isPresentingPanel: isPresentingPanel) {
        case .loadNow:
            load(incoming.take())
        case .holdUntilIdle:
            heldExternalFiles = incoming
            // Behind a panel, the panel is already in front. On the spinner,
            // open the popover so the user sees the request arrived.
            if !isPresentingPanel { onLoad?() }
        }
    }

    /// Loads held files if the model is no longer busy. Called where busy
    /// periods end: after the awaits in submitPassword() and save(), after a
    /// classification lands, and when a panel is cancelled.
    func resumeExternalOpen() {
        guard !heldExternalFiles.isEmpty,
            externalOpenAction(step: step, isPresentingPanel: isPresentingPanel) == .loadNow
        else { return }
        load(heldExternalFiles.take())
    }

    private func discardExternalFiles() {
        heldExternalFiles = IncomingFiles()
        onPanelConfirmed?()
    }

    func load(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        onLoad?()
        loadGeneration += 1
        let generation = loadGeneration
        // Leave any step that acts on the previous batch (Save, Unlock) right
        // away instead of when classification lands. Idle has no such action,
        // so it stays put and doesn't flash the "Unlocking…" spinner.
        if step != .idle { step = .working }
        Task {
            let classified = await Task.detached {
                urls.map { LoadedFile(url: $0, kind: FileKind(classify($0))) }
            }.value
            // Two rapid drops race: only the newest batch may apply.
            guard generation == loadGeneration else { return }
            files = classified
            password = ""
            verifiedPassword = nil
            passwordError = false
            savedURLs = []
            savedTo = nil
            step = Unlatch.step(afterLoading: classified.map(\.kind))
            // A request that arrived while this classification ran was held.
            resumeExternalOpen()
        }
    }

    // MARK: Password

    func submitPassword() {
        // No trimming: a real PDF password can legitimately start or end with
        // whitespace. Only a fully empty field does nothing.
        let attempt = password
        guard !attempt.isEmpty else { return }
        let targets = encryptedFiles.map(\.url)
        let generation = loadGeneration
        step = .working
        Task {
            // Runs on every exit, including a dropped result, so a request
            // held meanwhile is never stranded.
            defer { resumeExternalOpen() }
            let matched = await Task.detached {
                Set(targets.filter { passwordWorks(attempt, for: $0) })
            }.value
            guard generation == loadGeneration else { return }
            if matched.isEmpty {
                step = .password
                passwordError = true
                shakeCount += 1
            } else {
                verifiedPassword = attempt
                for index in files.indices
                where files[index].kind == .encrypted && !matched.contains(files[index].url) {
                    files[index].skipped = true
                }
                passwordError = false
                step = .destination
            }
        }
    }

    // MARK: Destination

    /// "Choose folder…" opens the picker right away; canceling keeps the
    /// previous selection. The popover stays open behind the panel, same as
    /// `browse()`.
    func chooseOtherFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        isPresentingPanel = true
        let response = panel.runModal()
        isPresentingPanel = false
        folderPanelClosed(url: response == .OK ? panel.url : nil)
    }

    /// What chooseOtherFolder() does once its panel closes; `nil` means
    /// cancelled. A confirm discards files held from outside and applies the
    /// folder, a cancel loads the held files.
    func folderPanelClosed(url: URL?) {
        guard let url else {
            resumeExternalOpen()
            return
        }
        discardExternalFiles()
        chosenFolder = url
        destination = .other
    }

    func save() {
        let option = destination
        let jobs = saveJobs(
            for: files, option: option,
            desktopFolder: desktopFolder, chosenFolder: chosenFolder,
            password: verifiedPassword)
        guard !jobs.isEmpty else { return }
        let generation = loadGeneration
        step = .working
        Task {
            defer { resumeExternalOpen() }
            // The concrete Error thrown by executeSaveJob is not Sendable, so
            // it's mapped to SaveFailure inside the detached closure — only
            // that Sendable outcome crosses back to the main actor.
            let outcomes = await Task.detached {
                jobs.map { job -> (source: URL, dest: URL, failure: SaveFailure?) in
                    do {
                        try executeSaveJob(job)
                        return (job.source, job.destination, nil)
                    } catch let error as UnlockError {
                        return (job.source, job.destination, SaveFailure(error))
                    } catch {
                        return (job.source, job.destination, .copyFailed)
                    }
                }
            }.value
            // The files are written, but a newer batch owns the rows and the
            // step now, so none of this outcome may land on it.
            guard generation == loadGeneration else { return }
            // Duplicate source URLs shouldn't happen — load(_:) doesn't dedupe
            // today, but nothing guarantees a future caller won't feed the
            // same file in twice — so uniqueKeysWithValues (which traps on a
            // collision) isn't safe here. Keep the first failure: outcomes
            // are in job order, so "first" is deterministic and matches what
            // the row would have shown had only one job run for that file.
            let failures = Dictionary(
                outcomes.compactMap { outcome in outcome.failure.map { (outcome.source, $0) } },
                uniquingKeysWith: { first, _ in first })
            let succeeded = outcomes.filter { $0.failure == nil }
            let succeededSources = Set(succeeded.map(\.source))
            for index in files.indices {
                let url = files[index].url
                if let failure = failures[url] {
                    files[index].failure = failure
                } else if succeededSources.contains(url) {
                    files[index].unlocked = true
                }
            }
            // An empty `succeeded` renders as the failure variant of the done
            // step: doneTitle(savedCount: 0) and no Show in Finder button.
            savedURLs = succeeded.map(\.dest)
            savedTo = doneSummary(destinations: savedURLs, option: option)
            step = .done
        }
    }

    // MARK: Launch at Login

    func refreshLoginItem() {
        loginItemStatus = loginItemService.status
    }

    /// Whatever happens, the menu item ends up showing the status the system
    /// reports afterwards, so a failed register or unregister snaps it back.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            switch loginItemAction(from: loginItemStatus, turningOn: on) {
            case .register: try loginItemService.register()
            case .unregister: try loginItemService.unregister()
            case .openSystemSettings: loginItemService.openSystemSettings()
            case .noChange: break
            }
        } catch {
            NSLog("Unlatch: changing the login item failed: %@", String(describing: error))
        }
        refreshLoginItem()
    }

    // MARK: Done

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
    }

    func reset() {
        loadGeneration += 1
        step = .idle
        files = []
        password = ""
        verifiedPassword = nil
        revealPassword = false
        passwordError = false
        destination = .suffix
        chosenFolder = nil
        savedURLs = []
        savedTo = nil
    }
}
