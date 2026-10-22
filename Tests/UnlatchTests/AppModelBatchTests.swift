import Foundation
import Testing

@testable import Unlatch

// A new load must never let the previous batch act on it: its Save has to
// disappear as soon as the load starts, and a save that finishes after a
// newer load or a reset must not apply its result. Today a load only starts from the idle step,
// but the Finder hand-off (Design/finder-quick-action.md, Goal 3) can start one
// from any step.

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

@MainActor @Test func aSaveThatFinishesAfterAResetIsDropped() async throws {
    let workspace = try Workspace()
    defer { workspace.remove() }
    let file = try workspace.plainPDF(named: "file.pdf")
    let output = workspace.folder.appending(path: "file-unlocked.pdf")
    let model = destinationModel(with: file)

    model.save()
    // One yield lets the save task start its detached write. Then block the
    // main actor, without yielding, until the write is on disk: the save's
    // completion can't run before the reset below bumps the generation.
    // A reset is used rather than a load because nothing lands afterwards to
    // overwrite what an unguarded completion would leave behind.
    await Task.yield()
    let deadline = Date.now.addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: output.path), Date.now < deadline {
        usleep(1_000)
    }
    #expect(FileManager.default.fileExists(atPath: output.path))

    model.reset()
    // Give the queued completion time to run.
    try await Task.sleep(for: .milliseconds(200))

    #expect(model.step == .idle)
    #expect(model.files.isEmpty)
    #expect(model.savedURLs.isEmpty)
    #expect(model.savedTo.isEmpty)
}
