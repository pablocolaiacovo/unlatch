import Foundation

@testable import Unlatch

/// A temporary folder holding copies of core fixtures, so saves write next to
/// them and nothing touches the fixtures themselves.
struct Workspace {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "UnlatchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func plainPDF(named name: String) throws -> URL {
        try fixture("plain.pdf", named: name)
    }

    func userLockedPDF(named name: String) throws -> URL {
        try fixture("user-locked.pdf", named: name)
    }

    private func fixture(_ fixtureName: String, named name: String) throws -> URL {
        let source = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "UnlatchCoreTests/Fixtures/\(fixtureName)")
        let copy = folder.appending(path: name)
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Polls on the main actor, yielding between checks, until `condition` holds.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5), _ condition: () -> Bool
) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try await Task.sleep(for: .milliseconds(5))
    }
    return true
}
