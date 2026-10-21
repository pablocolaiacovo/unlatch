import Foundation
import Testing

@testable import Unlatch

// Snapshot tests of every popover step, in light and dark. The references live under
// __Snapshots__/PopoverSnapshotTests/ and are recorded by CI only; see Design/snapshot-tests.md
// and RELEASING.md, "Snapshot tests".

/// Sample state for each popover step. Every value is set directly on `AppModel`: nothing calls
/// `load`, `submitPassword`, or `save`, because those start detached tasks, and no file has to
/// exist because `kind` is set instead of calling `classify`.
@MainActor
enum PopoverFixture: String, CaseIterable, Sendable {
    case idle, password, destination, working, done, donePartialFailure

    func makeModel() -> AppModel {
        // Never `AppModel()`: its default login item would ask SMAppService about the test tool.
        let model = AppModel(loginItemService: FixedLoginItem(status: .unavailable))
        switch self {
        case .idle:
            break
        case .password:
            model.files = [
                Self.file("Bank statement 2026-09.pdf", .encrypted),
                Self.file("Payslip September.pdf", .encrypted),
            ]
            model.password = "hunter2"
            model.passwordError = true
            model.step = .password
        case .destination:
            model.files = [
                Self.file("Bank statement 2026-09.pdf", .encrypted),
                Self.file("Lease agreement.pdf", .owner),
            ]
            model.destination = .suffix
            model.step = .destination
        case .working:
            model.files = [
                Self.file("Bank statement 2026-09.pdf", .encrypted),
                Self.file("Payslip September.pdf", .encrypted),
            ]
            model.step = .working
        case .done:
            var files = [
                Self.file("Bank statement 2026-09.pdf", .encrypted),
                Self.file("Payslip September.pdf", .encrypted),
            ]
            for index in files.indices { files[index].unlocked = true }
            model.files = files
            model.savedURLs = files.map { Self.unlockedURL(for: $0.url) }
            model.savedTo = doneSummary(destinations: model.savedURLs, option: .suffix)
            model.step = .done
        case .donePartialFailure:
            var files = [
                Self.file("Bank statement 2026-09.pdf", .encrypted),
                Self.file("Payslip September.pdf", .encrypted),
            ]
            files[0].unlocked = true
            files[1].failure = .writeFailed
            model.files = files
            model.savedURLs = [Self.unlockedURL(for: files[0].url)]
            model.savedTo = doneSummary(destinations: model.savedURLs, option: .suffix)
            model.step = .done
        }
        return model
    }

    /// Under the current user's home folder, so `abbreviatedPath` renders `~/Documents/...`
    /// on any account.
    private static func file(_ name: String, _ kind: FileKind) -> LoadedFile {
        LoadedFile(
            url: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents").appendingPathComponent(name),
            kind: kind)
    }

    private static func unlockedURL(for url: URL) -> URL {
        destinationURL(
            for: url, option: .suffix, desktopFolder: url.deletingLastPathComponent(),
            chosenFolder: nil)
    }
}

@MainActor
@Suite(
    .enabled("Snapshot references were recorded in a different rendering environment; see RELEASING.md") {
        await SnapshotGate.shouldRun()
    })
struct PopoverSnapshotTests {
    @Test(arguments: PopoverFixture.allCases)
    func popover(_ fixture: PopoverFixture) {
        assertPopoverSnapshot(fixture.makeModel(), named: fixture.rawValue)
    }

    #if DEBUG
    /// The footer's "Update Available" button, with no Sparkle object behind it.
    /// Debug only, like `AppUpdater.previewingUpdateAvailable()`.
    @Test func footerUpdateAvailable() {
        assertPopoverSnapshot(
            PopoverFixture.idle.makeModel(), updater: .previewingUpdateAvailable(),
            named: "footerUpdateAvailable")
    }
    #endif
}
