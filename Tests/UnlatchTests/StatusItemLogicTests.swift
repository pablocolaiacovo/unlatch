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
