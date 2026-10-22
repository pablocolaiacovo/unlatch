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

@Test func ownerRestrictedMapsToOwner() {
    #expect(FileKind(.ownerRestricted) == .owner)
}

@Test func notEncryptedMapsToPlain() {
    #expect(FileKind(.notEncrypted) == .plain)
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
    #expect(step(afterLoading: [.plain]) == .destination)
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

/// A row as plain values, with the note resolved in `language`. `RowInfo` holds a
/// `LocalizedStringResource`, which only compares equal to the same key, arguments, bundle and
/// locale, so tests compare the resolved text instead.
private struct RowText: Equatable {
    let badge: String
    let tone: RowTone
    let note: String

    init(_ info: RowInfo, _ language: String) {
        badge = info.badge
        tone = info.tone
        note = resolved(info.note, language)
    }

    init(badge: String, tone: RowTone, note: String) {
        self.badge = badge
        self.tone = tone
        self.note = note
    }
}

private func enRow(_ info: RowInfo) -> RowText { RowText(info, "en") }
private func esRow(_ info: RowInfo) -> RowText { RowText(info, "es") }

private func file(
    _ kind: FileKind, skipped: Bool = false, unlocked: Bool = false,
    failure: SaveFailure? = nil
) -> LoadedFile {
    var file = LoadedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), kind: kind)
    file.skipped = skipped
    file.unlocked = unlocked
    file.failure = failure
    return file
}

@Test func encryptedRowPendingAndDone() {
    let pending = enRow(rowInfo(for: file(.encrypted), done: false))
    #expect(pending == RowText(badge: "•", tone: .neutral, note: "Password protected"))

    let done = enRow(rowInfo(for: file(.encrypted, unlocked: true), done: true))
    #expect(done == RowText(badge: "✓", tone: .success, note: "Unlocked"))
}

@Test func skippedEncryptedRowKeepsPendingLookWhenDone() {
    let skipped = enRow(rowInfo(for: file(.encrypted, skipped: true), done: true))
    #expect(skipped == RowText(badge: "•", tone: .neutral, note: "Password protected"))
}

@Test func ownerRowPendingAndDone() {
    let pending = enRow(rowInfo(for: file(.owner), done: false))
    #expect(pending == RowText(
        badge: "i", tone: .warning, note: "No open password — permissions only"))

    let done = enRow(rowInfo(for: file(.owner, unlocked: true), done: true))
    #expect(done == RowText(
        badge: "i", tone: .warning, note: "Copied as-is — opens without a password"))
}

@Test func plainRowPendingAndDone() {
    let pending = enRow(rowInfo(for: file(.plain), done: false))
    #expect(pending == RowText(
        badge: "i", tone: .neutral, note: "Not encrypted — nothing to unlock"))

    let done = enRow(rowInfo(for: file(.plain, unlocked: true), done: true))
    #expect(done == RowText(
        badge: "i", tone: .neutral, note: "Not encrypted — copied as-is"))
}

@Test func plainRowsAreNeutralWhileOwnerRowsStayWarning() {
    for done in [false, true] {
        let plain = rowInfo(for: file(.plain, unlocked: done), done: done)
        #expect(plain.badge == "i")
        #expect(plain.tone == .neutral)
        let owner = rowInfo(for: file(.owner, unlocked: done), done: done)
        #expect(owner.badge == "i")
        #expect(owner.tone == .warning)
    }
}

@Test func plainAndOwnerNotesAreDistinct() {
    for language in ["en", "es"] {
        #expect(resolved(rowInfo(for: file(.plain), done: false).note, language)
            != resolved(rowInfo(for: file(.owner), done: false).note, language))
        #expect(resolved(rowInfo(for: file(.plain, unlocked: true), done: true).note, language)
            != resolved(rowInfo(for: file(.owner, unlocked: true), done: true).note, language))
    }
}

@Test func corruptRowAlwaysSkipped() {
    let info = enRow(rowInfo(for: file(.corrupt), done: false))
    #expect(info == RowText(badge: "!", tone: .error, note: "Not a readable PDF — skipped"))
    #expect(enRow(rowInfo(for: file(.corrupt), done: true)) == info)
}

// MARK: - Failed row mapping

@Test func failedEncryptedRowShowsDistinctErrorNotes() {
    #expect(enRow(rowInfo(for: file(.encrypted, failure: .wrongPassword), done: true))
        == RowText(badge: "!", tone: .error, note: "Password didn’t match — not saved"))
    #expect(enRow(rowInfo(for: file(.encrypted, failure: .unreadable), done: true))
        == RowText(badge: "!", tone: .error, note: "Couldn’t be read — not saved"))
    #expect(enRow(rowInfo(for: file(.encrypted, failure: .writeFailed), done: true))
        == RowText(badge: "!", tone: .error, note: "Couldn’t write the file — not saved"))
}

@Test func failedOwnerRowUsesCopyFailedFallback() {
    #expect(enRow(rowInfo(for: file(.owner, failure: .copyFailed), done: true))
        == RowText(badge: "!", tone: .error, note: "Couldn’t be copied — not saved"))
}

@Test func failureIsOnlyShownWhenDone() {
    // A failure recorded before the done step (shouldn't happen, but the
    // pending look must win if it ever did) never leaks into an earlier step.
    let pending = enRow(rowInfo(for: file(.encrypted, failure: .writeFailed), done: false))
    #expect(pending == RowText(badge: "•", tone: .neutral, note: "Password protected"))
}

@Test func unlockErrorMapsToMatchingSaveFailure() {
    #expect(SaveFailure(.wrongPassword) == .wrongPassword)
    #expect(SaveFailure(.unreadable) == .unreadable)
    #expect(SaveFailure(.writeFailed) == .writeFailed)
}

// MARK: - Display strings

@Test func passwordCopySingleVersusBatch() {
    let one = [file(.encrypted)]
    #expect(en(passwordTitle(encryptedCount: 1)) == "This PDF needs a password")
    #expect(en(passwordSubtitle(encrypted: one)) == "a.pdf")

    let two = [file(.encrypted), file(.encrypted)]
    #expect(en(passwordTitle(encryptedCount: 2)) == "2 files need a password")
    #expect(en(passwordSubtitle(encrypted: two))
        == "We’ll try the same password on all of them. Anything that doesn’t match gets skipped.")
}

@Test func doneTitleSingleVersusBatch() {
    #expect(en(doneTitle(savedCount: 1)) == "Saved")
    #expect(en(doneTitle(savedCount: 3)) == "3 files saved")
}

@Test func doneTitleZeroSavedIsFailure() {
    #expect(en(doneTitle(savedCount: 0)) == "Couldn’t save — nothing was written")
}

@Test func doneTitlePartialBatchReportsBoth() {
    #expect(en(doneTitle(savedCount: 3, failedCount: 2)) == "3 saved, 2 failed")
    #expect(en(doneTitle(savedCount: 1, failedCount: 1)) == "1 saved, 1 failed")
}

@Test func doneTitleAllFailedNamesTheCount() {
    #expect(en(doneTitle(savedCount: 0, failedCount: 1)) == "Couldn’t save — the file failed")
    #expect(en(doneTitle(savedCount: 0, failedCount: 3)) == "Couldn’t save — all 3 files failed")
}

/// `doneSummary` resolved in English, or `nil` when there is nothing to show.
private func summary(_ destinations: [URL], _ option: DestinationOption) -> String? {
    doneSummary(destinations: destinations, option: option).map(en)
}

@Test func doneSummaryFormats() {
    let a = URL(fileURLWithPath: "/tmp/Documents/A-unlocked.pdf")
    let b = URL(fileURLWithPath: "/tmp/Documents/B-unlocked.pdf")
    #expect(summary([a], .suffix) == "/tmp/Documents/A-unlocked.pdf")
    #expect(summary([a, b], .suffix) == "/tmp/Documents/…-unlocked.pdf")
    #expect(summary([a, b], .replace) == "/tmp/Documents/ (originals replaced)")
    #expect(summary([a, b], .desktop) == "/tmp/Documents/")
    #expect(doneSummary(destinations: [], option: .suffix) == nil)
}

@Test func doneSummarySpanningFoldersStatesTheSpread() {
    let a = URL(fileURLWithPath: "/tmp/Documents/A-unlocked.pdf")
    let b = URL(fileURLWithPath: "/tmp/Archive/B-unlocked.pdf")
    let c = URL(fileURLWithPath: "/tmp/Archive/C-unlocked.pdf")
    #expect(summary([a, b], .suffix) == "2 files in 2 folders")
    #expect(summary([a, b, c], .replace) == "3 files in 2 folders")
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
        file(.plain),
        file(.corrupt),
        file(.encrypted, skipped: true),
    ]
    let jobs = saveJobs(
        for: batch, option: .desktop,
        desktopFolder: desktop, chosenFolder: nil, password: "pw")
    #expect(jobs.count == 3)
    #expect(jobs[0].action == .unlock(password: "pw"))
    // Owner and plain files are copied byte-for-byte, never rewritten through unlock().
    #expect(jobs[1].action == .copy)
    #expect(jobs[2].action == .copy)
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
    #expect(en(destinationHint(
        option: .suffix, sample: source, desktopFolder: desktop, chosenFolder: nil
    )) == "/tmp/Documents/Q3-Financials-unlocked.pdf")
    #expect(en(destinationHint(
        option: .replace, sample: source, desktopFolder: desktop, chosenFolder: nil
    )) == "/tmp/Documents/Q3-Financials.pdf")
    #expect(en(destinationHint(
        option: .desktop, sample: source, desktopFolder: desktop, chosenFolder: nil
    )) == "/tmp/Desktop/")
    #expect(en(destinationHint(
        option: .other, sample: source, desktopFolder: desktop, chosenFolder: nil
    )) == "opens a save panel")
    #expect(en(destinationHint(
        option: .other, sample: source, desktopFolder: desktop,
        chosenFolder: URL(fileURLWithPath: "/tmp/Unlocked", isDirectory: true)
    )) == "/tmp/Unlocked/")
}

// MARK: - Version label

@Test func versionLabelForRelease() {
    #expect(en(versionLabel(version: "1.0.0", build: "42")) == "Version 1.0.0 (42)")
}

@Test func versionLabelPassesDescribeStringsThrough() {
    #expect(en(versionLabel(version: "0.0.0-abc1234", build: "7")) == "Version 0.0.0-abc1234 (7)")
    #expect(
        en(versionLabel(version: "1.0.0-3-gabc1234-dirty", build: "45"))
            == "Version 1.0.0-3-gabc1234-dirty (45)")
}

@Test func versionLabelFallsBackToDevWhenBothMissing() {
    #expect(en(versionLabel(version: nil, build: nil)) == "Version dev")
    #expect(en(versionLabel(version: "", build: "")) == "Version dev")
}

@Test func versionLabelWithOnlyOneValue() {
    #expect(en(versionLabel(version: "1.0.0", build: nil)) == "Version 1.0.0")
    #expect(en(versionLabel(version: nil, build: "42")) == "Version dev (42)")
}
