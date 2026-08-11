import Foundation
import PDFKit
import Testing
import UnlatchCore
@testable import Unlatch

/// A unique path in an existing scratch directory, for tests that write files.
private func scratchURL(ext: String = "pdf") -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("UnlatchAppTests", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
}

// MARK: - Classification mapping

@Test func userLockedMapsToEncrypted() {
    #expect(FileKind(.userLocked) == .encrypted)
}

@Test func ownerRestrictedAndPlainMapToOwner() {
    #expect(FileKind(.ownerRestricted) == .owner)
    #expect(FileKind(.notEncrypted) == .owner)
}

@Test func unreadableMapsToCorrupt() {
    #expect(FileKind(.unreadable) == .corrupt)
}

// MARK: - Step transitions after loading

@Test func anyEncryptedFileGoesToPassword() {
    #expect(step(afterLoading: [.owner, .encrypted, .corrupt]) == .password)
    #expect(step(afterLoading: [.encrypted]) == .password)
}

@Test func usableWithoutEncryptedGoesToDestination() {
    #expect(step(afterLoading: [.owner]) == .destination)
    #expect(step(afterLoading: [.owner, .corrupt]) == .destination)
}

@Test func allCorruptStaysIdle() {
    #expect(step(afterLoading: [.corrupt, .corrupt]) == .idle)
    #expect(step(afterLoading: []) == .idle)
}

// MARK: - Destination URLs

private let source = URL(fileURLWithPath: "/tmp/Documents/Q3-Financials.pdf")
private let desktop = URL(fileURLWithPath: "/tmp/Desktop", isDirectory: true)

@Test func suffixOptionInsertsUnlockedBeforeExtension() {
    let url = destinationURL(for: source, option: .suffix, desktopFolder: desktop, chosenFolder: nil)
    #expect(url.path == "/tmp/Documents/Q3-Financials-unlocked.pdf")
}

@Test func replaceOptionOverwritesOriginal() {
    let url = destinationURL(for: source, option: .replace, desktopFolder: desktop, chosenFolder: nil)
    #expect(url.path == source.path)
}

@Test func desktopOptionKeepsFilename() {
    let url = destinationURL(for: source, option: .desktop, desktopFolder: desktop, chosenFolder: nil)
    #expect(url.path == "/tmp/Desktop/Q3-Financials.pdf")
}

@Test func chosenFolderOptionKeepsFilename() {
    let chosen = URL(fileURLWithPath: "/tmp/Unlocked", isDirectory: true)
    let url = destinationURL(for: source, option: .other, desktopFolder: desktop, chosenFolder: chosen)
    #expect(url.path == "/tmp/Unlocked/Q3-Financials.pdf")
}

@Test func chosenFolderFallsBackToDesktop() {
    let url = destinationURL(for: source, option: .other, desktopFolder: desktop, chosenFolder: nil)
    #expect(url.path == "/tmp/Desktop/Q3-Financials.pdf")
}

// MARK: - Row mapping

private func file(_ kind: FileKind, skipped: Bool = false, unlocked: Bool = false) -> LoadedFile {
    var file = LoadedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), kind: kind)
    file.skipped = skipped
    file.unlocked = unlocked
    return file
}

@Test func encryptedRowPendingAndDone() {
    let pending = rowInfo(for: file(.encrypted), done: false)
    #expect(pending == RowInfo(badge: "•", tone: .neutral, note: "Password protected"))

    let done = rowInfo(for: file(.encrypted, unlocked: true), done: true)
    #expect(done == RowInfo(badge: "✓", tone: .success, note: "Unlocked"))
}

@Test func skippedEncryptedRowKeepsPendingLookWhenDone() {
    let skipped = rowInfo(for: file(.encrypted, skipped: true), done: true)
    #expect(skipped == RowInfo(badge: "•", tone: .neutral, note: "Password protected"))
}

@Test func ownerRowPendingAndDone() {
    let pending = rowInfo(for: file(.owner), done: false)
    #expect(pending == RowInfo(
        badge: "i", tone: .warning, note: "No open password — permissions only"))

    let done = rowInfo(for: file(.owner, unlocked: true), done: true)
    #expect(done == RowInfo(
        badge: "i", tone: .warning, note: "Copied as-is — opens without a password"))
}

@Test func corruptRowAlwaysSkipped() {
    let info = rowInfo(for: file(.corrupt), done: false)
    #expect(info == RowInfo(badge: "!", tone: .error, note: "Not a readable PDF — skipped"))
    #expect(rowInfo(for: file(.corrupt), done: true) == info)
}

// MARK: - Display strings

@Test func headerNoteCountsFiles() {
    #expect(headerNote(fileCount: 0) == "Remove PDF passwords")
    #expect(headerNote(fileCount: 1) == "1 file")
    #expect(headerNote(fileCount: 4) == "4 files")
}

@Test func passwordCopySingleVersusBatch() {
    let one = [file(.encrypted)]
    #expect(passwordTitle(encryptedCount: 1) == "This PDF needs a password")
    #expect(passwordSubtitle(encrypted: one) == "a.pdf")

    let two = [file(.encrypted), file(.encrypted)]
    #expect(passwordTitle(encryptedCount: 2) == "2 files need a password")
    #expect(passwordSubtitle(encrypted: two)
        == "We’ll try the same password on all of them. Anything that doesn’t match gets skipped.")
}

@Test func doneTitleSingleVersusBatch() {
    #expect(doneTitle(savedCount: 1) == "Saved")
    #expect(doneTitle(savedCount: 3) == "3 files saved")
}

@Test func doneTitleZeroSavedIsFailure() {
    #expect(doneTitle(savedCount: 0) == "Couldn’t save — nothing was written")
}

@Test func doneSummaryFormats() {
    let a = URL(fileURLWithPath: "/tmp/Documents/A-unlocked.pdf")
    let b = URL(fileURLWithPath: "/tmp/Documents/B-unlocked.pdf")
    #expect(doneSummary(destinations: [a], option: .suffix) == "/tmp/Documents/A-unlocked.pdf")
    #expect(doneSummary(destinations: [a, b], option: .suffix) == "/tmp/Documents/…-unlocked.pdf")
    #expect(doneSummary(destinations: [a, b], option: .replace)
        == "/tmp/Documents/ (originals replaced)")
    #expect(doneSummary(destinations: [a, b], option: .desktop) == "/tmp/Documents/")
    #expect(doneSummary(destinations: [], option: .suffix) == "")
}

@Test func doneSummarySpanningFoldersStatesTheSpread() {
    let a = URL(fileURLWithPath: "/tmp/Documents/A-unlocked.pdf")
    let b = URL(fileURLWithPath: "/tmp/Archive/B-unlocked.pdf")
    let c = URL(fileURLWithPath: "/tmp/Archive/C-unlocked.pdf")
    #expect(doneSummary(destinations: [a, b], option: .suffix) == "2 files in 2 folders")
    #expect(doneSummary(destinations: [a, b, c], option: .replace) == "3 files in 2 folders")
}

// MARK: - Save jobs

@Test func saveJobsPassPasswordThroughExactly() {
    // A password with surrounding whitespace must reach unlock() untouched —
    // it is the exact string the password step verified.
    let spaced = "  hunter2  "
    let jobs = saveJobs(
        for: [file(.encrypted)], option: .suffix,
        desktopFolder: desktop, chosenFolder: nil, password: spaced)
    #expect(jobs.count == 1)
    #expect(jobs[0].action == .unlock(password: spaced))
}

@Test func saveJobsCopyOwnerFilesAndSkipTheRest() {
    let batch = [
        file(.encrypted),
        file(.owner),
        file(.corrupt),
        file(.encrypted, skipped: true),
    ]
    let jobs = saveJobs(
        for: batch, option: .desktop,
        desktopFolder: desktop, chosenFolder: nil, password: "pw")
    #expect(jobs.count == 2)
    #expect(jobs[0].action == .unlock(password: "pw"))
    // Owner files are copied byte-for-byte, never rewritten through unlock().
    #expect(jobs[1].action == .copy)
}

@Test func copyJobPreservesBytesExactly() throws {
    let source = scratchURL()
    let destination = scratchURL()
    let bytes = Data((0..<512).map { _ in UInt8.random(in: .min ... .max) })
    try bytes.write(to: source)

    try executeSaveJob(SaveJob(source: source, destination: destination, action: .copy))
    #expect(try Data(contentsOf: destination) == bytes)

    // "Replace original" copies a file onto itself: a no-op success.
    try executeSaveJob(SaveJob(source: source, destination: source, action: .copy))
    #expect(try Data(contentsOf: source) == bytes)
}

/// Locks the verify/save contract end to end: the exact string that
/// `passwordWorks` accepts — including surrounding whitespace — is the one
/// `unlock` succeeds with, and its trimmed variant fails both.
@Test func verifyAndUnlockAgreeOnWhitespacePassword() throws {
    let spaced = "  spaced pw  "
    let locked = scratchURL()
    let doc = PDFDocument()
    doc.insert(PDFPage(), at: 0)
    let wrote = doc.write(to: locked, withOptions: [
        .userPasswordOption: spaced,
        .ownerPasswordOption: spaced,
    ])
    try #require(wrote)
    try #require(classify(locked) == .userLocked)

    #expect(passwordWorks(spaced, for: locked))
    #expect(!passwordWorks(spaced.trimmingCharacters(in: .whitespaces), for: locked))

    let destination = scratchURL()
    try executeSaveJob(SaveJob(
        source: locked, destination: destination, action: .unlock(password: spaced)))
    #expect(classify(destination) == .notEncrypted)
}

@Test func destinationHints() {
    #expect(destinationHint(
        option: .suffix, sample: source, desktopFolder: desktop, chosenFolder: nil
    ) == "/tmp/Documents/Q3-Financials-unlocked.pdf")
    #expect(destinationHint(
        option: .replace, sample: source, desktopFolder: desktop, chosenFolder: nil
    ) == "/tmp/Documents/Q3-Financials.pdf")
    #expect(destinationHint(
        option: .desktop, sample: source, desktopFolder: desktop, chosenFolder: nil
    ) == "/tmp/Desktop/")
    #expect(destinationHint(
        option: .other, sample: source, desktopFolder: desktop, chosenFolder: nil
    ) == "opens a save panel")
    #expect(destinationHint(
        option: .other, sample: source, desktopFolder: desktop,
        chosenFolder: URL(fileURLWithPath: "/tmp/Unlocked", isDirectory: true)
    ) == "/tmp/Unlocked/")
}
