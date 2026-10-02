import Foundation
import Observation
import ServiceManagement
import Testing
@testable import Unlatch

// Launch at Login (issue #16): the pure status-to-UI mapping, and AppModel
// driving a fake login item so no test touches the real SMAppService.

// MARK: - SMAppService.Status mapping

@Test func smAppServiceStatusMapsToLoginItemStatus() {
    #expect(LoginItemStatus(.enabled) == .enabled)
    #expect(LoginItemStatus(.notRegistered) == .disabled)
    #expect(LoginItemStatus(.requiresApproval) == .requiresApproval)
}

@Test func neverRegisteredBundleIsDisabledNotUnavailable() {
    #expect(LoginItemStatus(.notFound) == .disabled)
}

// MARK: - loginItemControl

@Test func loginItemControlIsOnOnlyWhenEnabled() {
    #expect(loginItemControl(for: .enabled).isOn == true)
    #expect(loginItemControl(for: .disabled).isOn == false)
    #expect(loginItemControl(for: .requiresApproval).isOn == false)
    #expect(loginItemControl(for: .unavailable).isOn == false)
}

@Test func loginItemControlIsDisabledOnlyWhenUnavailable() {
    #expect(loginItemControl(for: .enabled).isEnabled == true)
    #expect(loginItemControl(for: .disabled).isEnabled == true)
    #expect(loginItemControl(for: .requiresApproval).isEnabled == true)
    #expect(loginItemControl(for: .unavailable).isEnabled == false)
}

@Test func loginItemControlPointsAtSystemSettingsWhenApprovalIsNeeded() {
    #expect(loginItemControl(for: .requiresApproval).help.contains("Login Items"))
}

// MARK: - loginItemAction

@Test func loginItemActionTurningOn() {
    #expect(loginItemAction(from: .disabled, turningOn: true) == .register)
    #expect(loginItemAction(from: .requiresApproval, turningOn: true) == .openSystemSettings)
    #expect(loginItemAction(from: .enabled, turningOn: true) == .noChange)
    #expect(loginItemAction(from: .unavailable, turningOn: true) == .noChange)
}

@Test func loginItemActionTurningOff() {
    #expect(loginItemAction(from: .enabled, turningOn: false) == .unregister)
    #expect(loginItemAction(from: .requiresApproval, turningOn: false) == .unregister)
    #expect(loginItemAction(from: .disabled, turningOn: false) == .noChange)
    #expect(loginItemAction(from: .unavailable, turningOn: false) == .noChange)
}

// MARK: - AppModel

@MainActor
private final class FakeLoginItem: LoginItemService {
    struct Failure: Error {}

    var status: LoginItemStatus
    var fails = false
    private(set) var calls: [String] = []

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {
        calls.append("register")
        if fails { throw Failure() }
        status = .enabled
    }

    func unregister() throws {
        calls.append("unregister")
        if fails { throw Failure() }
        status = .disabled
    }

    func openSystemSettings() {
        calls.append("openSystemSettings")
    }
}

@MainActor @Test func appModelReadsTheSystemStatusAtInit() {
    let model = AppModel(loginItemService: FakeLoginItem(status: .enabled))
    #expect(model.loginItemStatus == .enabled)
    #expect(model.loginItem.isOn == true)
}

@MainActor @Test func appModelRegistersAndUnregisters() {
    let fake = FakeLoginItem(status: .disabled)
    let model = AppModel(loginItemService: fake)
    model.setLaunchAtLogin(true)
    #expect(model.loginItemStatus == .enabled)
    model.setLaunchAtLogin(false)
    #expect(model.loginItemStatus == .disabled)
    #expect(fake.calls == ["register", "unregister"])
}

@MainActor @Test func appModelSnapsBackWhenRegisterFails() {
    let fake = FakeLoginItem(status: .disabled)
    fake.fails = true
    let model = AppModel(loginItemService: fake)
    model.setLaunchAtLogin(true)
    #expect(fake.calls == ["register"])
    #expect(model.loginItemStatus == .disabled)
    #expect(model.loginItem.isOn == false)
}

@MainActor @Test func appModelOpensSystemSettingsInsteadOfRegisteringWhenApprovalIsNeeded() {
    let fake = FakeLoginItem(status: .requiresApproval)
    let model = AppModel(loginItemService: fake)
    model.setLaunchAtLogin(true)
    #expect(fake.calls == ["openSystemSettings"])
    #expect(model.loginItemStatus == .requiresApproval)
}

@MainActor @Test func appModelPicksUpAChangeMadeInSystemSettings() {
    let fake = FakeLoginItem(status: .enabled)
    let model = AppModel(loginItemService: fake)
    fake.status = .requiresApproval
    #expect(model.loginItem.isOn == true)
    model.refreshLoginItem()
    #expect(model.loginItem.isOn == false)
}

/// `onChange` is `@Sendable`; the observation fires synchronously on the main
/// actor here, so an unchecked box is safe.
private final class FiredFlag: @unchecked Sendable {
    var value = false
}

/// True when `body` makes an observer of `loginItemRevision` fire.
@MainActor private func revisionChanges(_ model: AppModel, during body: () -> Void) -> Bool {
    let fired = FiredFlag()
    withObservationTracking {
        _ = model.loginItemRevision
    } onChange: {
        fired.value = true
    }
    body()
    return fired.value
}

@MainActor @Test func failedRegisterStillNotifiesObservers() {
    let fake = FakeLoginItem(status: .disabled)
    fake.fails = true
    let model = AppModel(loginItemService: fake)
    #expect(revisionChanges(model) { model.setLaunchAtLogin(true) })
    #expect(model.loginItemStatus == .disabled)
}

@MainActor @Test func openingSystemSettingsStillNotifiesObservers() {
    let fake = FakeLoginItem(status: .requiresApproval)
    let model = AppModel(loginItemService: fake)
    #expect(revisionChanges(model) { model.setLaunchAtLogin(true) })
    #expect(model.loginItemStatus == .requiresApproval)
}

@MainActor @Test func refreshWithAnUnchangedStatusNotifiesObservers() {
    let model = AppModel(loginItemService: FakeLoginItem(status: .enabled))
    #expect(revisionChanges(model) { model.refreshLoginItem() })
}
