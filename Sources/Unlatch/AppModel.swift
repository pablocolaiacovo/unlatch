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
    var dragging = false

    var password = ""
    var revealPassword = false
    var passwordError = false
    /// Incremented on each failed attempt to drive the shake animation.
    var shakeCount = 0

    var destination: DestinationOption = .suffix
    var chosenFolder: URL?

    var savedURLs: [URL] = []
    var savedTo = ""

    var desktopFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    // MARK: Derived state

    var encryptedFiles: [LoadedFile] { files.filter { $0.kind == .encrypted } }
    var usableFiles: [LoadedFile] { files.filter { $0.kind != .corrupt && !$0.skipped } }
    /// The persistent rows section shows whenever files are loaded, except
    /// while the spinner is up.
    var showsFileRows: Bool { !files.isEmpty && step != .working }
    var headerText: String { headerNote(fileCount: files.count) }
    /// Sample file for the destination hints: the first usable one.
    var sampleFile: URL? { usableFiles.first?.url }

    // MARK: Loading

    func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            load(panel.urls)
        }
    }

    func load(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        dragging = false
        Task {
            let classified = await Task.detached {
                urls.map { LoadedFile(url: $0, kind: FileKind(classify($0))) }
            }.value
            files = classified
            password = ""
            passwordError = false
            step = Unlatch.step(afterLoading: classified.map(\.kind))
        }
    }

    // MARK: Password

    func submitPassword() {
        let attempt = password.trimmingCharacters(in: .whitespaces)
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
    /// previous selection.
    func chooseOtherFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            chosenFolder = url
            destination = .other
        }
    }

    func save() {
        let option = destination
        let desktop = desktopFolder
        let chosen = chosenFolder
        let jobs: [(source: URL, dest: URL, password: String?)] = usableFiles.map { file in
            (
                source: file.url,
                dest: destinationURL(
                    for: file.url, option: option,
                    desktopFolder: desktop, chosenFolder: chosen),
                password: file.kind == .encrypted ? password : nil
            )
        }
        guard !jobs.isEmpty else { return }
        step = .working
        Task {
            let succeeded = await Task.detached {
                jobs.compactMap { job -> (source: URL, dest: URL)? in
                    do {
                        try unlock(job.source, password: job.password, destination: job.dest)
                        return (job.source, job.dest)
                    } catch {
                        return nil
                    }
                }
            }.value
            let sources = Set(succeeded.map(\.source))
            for index in files.indices where sources.contains(files[index].url) {
                files[index].unlocked = true
            }
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
        revealPassword = false
        passwordError = false
        destination = .suffix
        chosenFolder = nil
        savedURLs = []
        savedTo = ""
    }
}
