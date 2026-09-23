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
    /// The in-popover drop zone's `isTargeted` state only. The status item's
    /// own hover highlight is tracked separately by `StatusItemController`
    /// and does not set this, so hovering the icon never lights up the zone.
    var dragging = false

    var password = ""
    /// The exact string `passwordWorks` accepted at the password step. save()
    /// must pass this same string to `unlock` — never a re-read or normalized
    /// copy of `password` — so verify and save can never disagree.
    private(set) var verifiedPassword: String?
    var revealPassword = false
    var passwordError = false
    /// Incremented on each failed attempt to drive the shake animation.
    var shakeCount = 0

    /// Bumped on every load; a finishing classification task from an older
    /// generation is stale and its result is dropped.
    private var loadGeneration = 0

    var destination: DestinationOption = .suffix
    var chosenFolder: URL?

    var savedURLs: [URL] = []
    var savedTo = ""

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

    var encryptedFiles: [LoadedFile] { files.filter { $0.kind == .encrypted } }
    var usableFiles: [LoadedFile] { files.filter { $0.kind != .corrupt && !$0.skipped } }
    /// Files `save()` attempted and that did not write, for the done step's title.
    var failedCount: Int { files.count { $0.failure != nil } }
    /// The persistent rows section shows whenever files are loaded, except
    /// while the spinner is up.
    var showsFileRows: Bool { !files.isEmpty && step != .working }
    var headerText: String { headerNote(fileCount: files.count) }
    /// Sample file for the destination hints: the first usable one.
    var sampleFile: URL? { usableFiles.first?.url }

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
        if panel.runModal() == .OK {
            load(panel.urls)
        }
    }

    func load(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        onLoad?()
        dragging = false
        loadGeneration += 1
        let generation = loadGeneration
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
            step = Unlatch.step(afterLoading: classified.map(\.kind))
        }
    }

    // MARK: Password

    func submitPassword() {
        // No trimming: a real PDF password can legitimately start or end with
        // whitespace. Only a fully empty field does nothing.
        let attempt = password
        guard !attempt.isEmpty else { return }
        let targets = encryptedFiles.map(\.url)
        step = .working
        Task {
            let matched = await Task.detached {
                Set(targets.filter { passwordWorks(attempt, for: $0) })
            }.value
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
        if panel.runModal() == .OK, let url = panel.url {
            chosenFolder = url
            destination = .other
        }
    }

    func save() {
        let option = destination
        let jobs = saveJobs(
            for: files, option: option,
            desktopFolder: desktopFolder, chosenFolder: chosenFolder,
            password: verifiedPassword)
        guard !jobs.isEmpty else { return }
        step = .working
        Task {
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

    // MARK: Done

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
    }

    func reset() {
        step = .idle
        files = []
        dragging = false
        password = ""
        verifiedPassword = nil
        revealPassword = false
        passwordError = false
        destination = .suffix
        chosenFolder = nil
        savedURLs = []
        savedTo = ""
    }
}
