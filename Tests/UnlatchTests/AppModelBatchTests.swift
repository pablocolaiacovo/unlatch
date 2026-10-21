import Foundation
import Testing

@testable import Unlatch

// A new load must never let the previous batch act on it: its Save has to
// disappear as soon as the load starts, and a save that finishes after the
// load must not apply its result. Today a load only starts from the idle step,
// but the Finder hand-off (Design/finder-quick-action.md, Goal 3) can start one
// from any step.

/// A temporary folder holding copies of the plain fixture, so suffix saves
/// write next to them and nothing touches the fixtures themselves.
private struct Workspace {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "AppModelBatchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func plainPDF(named name: String) throws -> URL {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "UnlatchCoreTests/Fixtures/plain.pdf")
        let copy = folder.appending(path: name)
        try FileManager.default.copyItem(at: fixture, to: copy)
        return copy
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Polls on the main actor, yielding between checks, until `condition` holds.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(5), _ condition: () -> Bool
) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@MainActor
private func destinationModel(with url: URL) -> AppModel {
    let model = AppModel(loginItemService: FixedLoginItem(status: .unavailable))
    model.files = [LoadedFile(url: url, kind: .plain)]
    model.destination = .suffix
    model.step = .destination
    return model
}

@MainActor @Test func loadHidesThePreviousBatchsSaveRightAway() async throws {
    let workspace = try Workspace()
    defer { workspace.remove() }
    let old = try workspace.plainPDF(named: "old.pdf")
    let new = try workspace.plainPDF(named: "new.pdf")
    let model = destinationModel(with: old)

    model.load([new])

    // Before classification lands, the step that shows Save must be gone.
    #expect(model.step == .working)
    #expect(try await waitUntil { model.files.map(\.url) == [new] })
    #expect(model.step == .destination)
}

@MainActor @Test func aSaveThatFinishesAfterANewLoadIsDropped() async throws {
    let workspace = try Workspace()
    defer { workspace.remove() }
    let old = try workspace.plainPDF(named: "old.pdf")
    let new = try workspace.plainPDF(named: "new.pdf")
    let oldOutput = workspace.folder.appending(path: "old-unlocked.pdf")
    let model = destinationModel(with: old)

    model.save()
    // One yield lets the save task start its detached write. Then block the
    // main actor, without yielding, until the write is on disk, so the save's
    // completion is usually still queued when the load below bumps the
    // generation. Other main-actor tests running in parallel can let the
    // completion land first; then the load must clear what it left instead.
    // Either way, nothing of the old save may survive the new batch.
    await Task.yield()
    let deadline = Date.now.addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: oldOutput.path), Date.now < deadline {
        usleep(1_000)
    }
    #expect(FileManager.default.fileExists(atPath: oldOutput.path))
    usleep(100_000)

    model.load([new])

    #expect(try await waitUntil { model.files.map(\.url) == [new] })
    #expect(model.step == .destination)
    #expect(model.savedURLs.isEmpty)
    #expect(model.savedTo.isEmpty)
    #expect(model.files.allSatisfy { !$0.unlocked && $0.failure == nil })
}
