import Foundation
import PDFKit
import UnlatchCore

// Pure app logic, kept off the main actor and free of UI types so it can be
// unit-tested directly. The view model calls into these functions.

/// The design's three file kinds, folded down from `Classification`.
/// `.notEncrypted` joins `.ownerRestricted` under `owner`: both are usable
/// files with no open password. Owner files are copied to the destination
/// byte-for-byte (see `saveJobs`), so the "Copied as-is — opens without a
/// password" copy is literally true for either.
enum FileKind: Equatable, Sendable {
    case encrypted, owner, corrupt

    init(_ classification: Classification) {
        switch classification {
        case .userLocked: self = .encrypted
        case .ownerRestricted, .notEncrypted: self = .owner
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

    var label: String {
        switch self {
        case .suffix: "Same folder, add “-unlocked”"
        case .replace: "Same folder, replace original"
        case .desktop: "Desktop"
        case .other: "Choose folder…"
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

    init(url: URL, kind: FileKind) {
        self.id = UUID()
        self.url = url
        self.kind = kind
    }

    var name: String { url.lastPathComponent }
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
func headerNote(fileCount: Int) -> String {
    guard fileCount > 0 else { return "Remove PDF passwords" }
    return fileCount == 1 ? "1 file" : "\(fileCount) files"
}

func passwordTitle(encryptedCount: Int) -> String {
    encryptedCount > 1 ? "\(encryptedCount) files need a password" : "This PDF needs a password"
}

func passwordSubtitle(encrypted: [LoadedFile]) -> String {
    if encrypted.count > 1 {
        return "We’ll try the same password on all of them. Anything that doesn’t match gets skipped."
    }
    return encrypted.first?.name ?? ""
}

/// Zero saved files is the failure state: nothing was written, so the step
/// must not read as a success.
func doneTitle(savedCount: Int) -> String {
    if savedCount == 0 { return "Couldn’t save — nothing was written" }
    return savedCount > 1 ? "\(savedCount) files saved" : "Saved"
}

/// The monospaced "where it went" line on the done step. A single file shows
/// its full path; a batch in one folder summarizes that folder the way the
/// design does; a batch spanning folders states the spread truthfully.
func doneSummary(destinations: [URL], option: DestinationOption) -> String {
    guard let first = destinations.first else { return "" }
    if destinations.count == 1 { return abbreviatedPath(first) }

    let folders = Set(destinations.map { $0.deletingLastPathComponent().standardizedFileURL.path })
    guard folders.count == 1 else {
        return "\(destinations.count) files in \(folders.count) folders"
    }

    let dir = abbreviatedPath(first.deletingLastPathComponent())
    switch option {
    case .suffix: return dir + "/…-unlocked.pdf"
    case .replace: return dir + "/ (originals replaced)"
    case .desktop, .other: return dir + "/"
    }
}

/// The monospaced hint under each destination radio option, computed from the
/// first usable file so the paths are real rather than the design's samples.
func destinationHint(
    option: DestinationOption,
    sample: URL?,
    desktopFolder: URL,
    chosenFolder: URL?
) -> String {
    switch option {
    case .suffix:
        guard let sample else { return "next to the original" }
        return abbreviatedPath(destinationURL(
            for: sample, option: .suffix, desktopFolder: desktopFolder, chosenFolder: nil))
    case .replace:
        guard let sample else { return "overwrites the original" }
        return abbreviatedPath(sample)
    case .desktop:
        return abbreviatedPath(desktopFolder) + "/"
    case .other:
        guard let chosenFolder else { return "opens a save panel" }
        return abbreviatedPath(chosenFolder) + "/"
    }
}

// MARK: - File rows

/// Semantic badge tone; the view maps tones to the design's exact colors.
enum RowTone: Equatable, Sendable {
    case neutral, success, warning, error
}

struct RowInfo: Equatable, Sendable {
    let badge: String
    let tone: RowTone
    let note: String
}

/// Badge and note for one file row, matching the design's `buildRows`.
/// An encrypted file whose password didn't match keeps its pending look —
/// it was skipped, not unlocked.
func rowInfo(for file: LoadedFile, done: Bool) -> RowInfo {
    switch file.kind {
    case .corrupt:
        return RowInfo(badge: "!", tone: .error, note: "Not a readable PDF — skipped")
    case .owner:
        return RowInfo(
            badge: "i", tone: .warning,
            note: done && file.unlocked
                ? "Copied as-is — opens without a password"
                : "No open password — permissions only")
    case .encrypted:
        if done && file.unlocked {
            return RowInfo(badge: "✓", tone: .success, note: "Unlocked")
        }
        return RowInfo(badge: "•", tone: .neutral, note: "Password protected")
    }
}

// MARK: - PDF helpers (blocking; call off the main actor)

/// True when `password` opens the document (or it needs no password at all).
func passwordWorks(_ password: String, for url: URL) -> Bool {
    guard let doc = PDFDocument(url: url) else { return false }
    if !doc.isLocked { return true }
    return doc.unlock(withPassword: password)
}
