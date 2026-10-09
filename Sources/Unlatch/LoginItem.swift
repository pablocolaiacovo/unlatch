import Foundation
import ServiceManagement

/// The app's login item, behind a protocol so `AppModel` can be tested with
/// a fake. The system is the only store of whether Unlatch opens at login:
/// nothing is kept in `UserDefaults`, because a copy there would go stale
/// the moment the user changes Login Items in System Settings.
@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// `SMAppService.mainApp`: registers the running app bundle itself, with no
/// helper app or launch agent plist. Needs a real bundle with a bundle
/// identifier; a bare SwiftPM binary (no bundle identifier) reports
/// `.unavailable`.
@MainActor
struct SystemLoginItem: LoginItemService {
    var status: LoginItemStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        return LoginItemStatus(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .disabled
        case .requiresApproval: self = .requiresApproval
        // A bundle that has never been registered reports `.notFound`, and
        // `register()` is what turns it into `.enabled`.
        case .notFound: self = .disabled
        @unknown default: self = .unavailable
        }
    }
}
