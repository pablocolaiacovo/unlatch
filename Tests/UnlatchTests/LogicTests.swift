import Foundation
import Testing
import UnlatchCore
@testable import Unlatch

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
