import Foundation
import Testing
@testable import Unlatch

// Pure logic behind the AppKit status item (Design/status-item-popover.md,
// task 1): the lock glyph and the state it's derived from.

// MARK: - hasLockedWork

@Test func hasLockedWorkFalseWhenNoFilesAreLoaded() {
    #expect(hasLockedWork([]) == false)
}

@Test func hasLockedWorkTrueForAnEncryptedFileNotYetUnlocked() {
    let file = LoadedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), kind: .encrypted)
    #expect(hasLockedWork([file]) == true)
}

@Test func hasLockedWorkFalseOnceTheEncryptedFileIsUnlocked() {
    var file = LoadedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), kind: .encrypted)
    file.unlocked = true
    #expect(hasLockedWork([file]) == false)
}

@Test func hasLockedWorkFalseForOwnerOnlyOrCorruptFiles() {
    let owner = LoadedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), kind: .owner)
    let corrupt = LoadedFile(url: URL(fileURLWithPath: "/tmp/b.pdf"), kind: .corrupt)
    #expect(hasLockedWork([owner, corrupt]) == false)
}

@Test func hasLockedWorkTrueForAMixWithOnePendingEncryptedFile() {
    var alreadyUnlocked = LoadedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), kind: .encrypted)
    alreadyUnlocked.unlocked = true
    let stillLocked = LoadedFile(url: URL(fileURLWithPath: "/tmp/b.pdf"), kind: .encrypted)
    let owner = LoadedFile(url: URL(fileURLWithPath: "/tmp/c.pdf"), kind: .owner)
    #expect(hasLockedWork([alreadyUnlocked, stillLocked, owner]) == true)
}

// MARK: - statusSymbolName

@Test func statusSymbolNameIsLockWhileWorkIsLocked() {
    #expect(statusSymbolName(hasLockedWork: true) == "lock")
}

@Test func statusSymbolNameIsLockOpenOtherwise() {
    #expect(statusSymbolName(hasLockedWork: false) == "lock.open")
}

// MARK: - statusItemPresentation

@Test(arguments: [true, false])
func statusItemPresentationShowsTheDotOnlyWhenAnUpdateIsAvailable(hasLockedWork: Bool) {
    let update = statusItemPresentation(hasLockedWork: hasLockedWork, updateState: .updateAvailable)
    #expect(update.symbolName == statusSymbolName(hasLockedWork: hasLockedWork))
    #expect(update.showsUpdateBadge)
    #expect(update.accessibilityValue.map(en) == "Update available")
    #expect(en(update.toolTip) == "Unlatch: update available")

    let check = statusItemPresentation(hasLockedWork: hasLockedWork, updateState: .check)
    #expect(check.symbolName == statusSymbolName(hasLockedWork: hasLockedWork))
    #expect(!check.showsUpdateBadge)
    #expect(check.accessibilityValue == nil)
    #expect(en(check.toolTip) == "Unlatch")
}

@Test(arguments: [UpdateButtonState.hidden, .checkDisabled])
func statusItemPresentationHasNoDotWhenUpdatesAreUnavailable(state: UpdateButtonState) {
    let presentation = statusItemPresentation(hasLockedWork: false, updateState: state)
    #expect(!presentation.showsUpdateBadge)
    #expect(presentation.accessibilityValue == nil)
    #expect(en(presentation.toolTip) == "Unlatch")
}

@Test(arguments: [UpdateButtonState.hidden, .checkDisabled, .check, .updateAvailable],
      [true, false])
func statusItemDotAgreesWithTheFooterIndicator(state: UpdateButtonState, hasLockedWork: Bool) {
    let presentation = statusItemPresentation(hasLockedWork: hasLockedWork, updateState: state)
    #expect(presentation.showsUpdateBadge == updateFooterPresentation(for: state).showsUpdateIndicator)
}

@Test func statusItemPresentationCopy() {
    #expect(StatusItemPresentation.accessibilityLabel == "Unlatch")
    #expect(en(StatusItemPresentation.updateAvailableValue) == "Update available")
    #expect(en(StatusItemPresentation.updateAvailableToolTip) == "Unlatch: update available")
}
