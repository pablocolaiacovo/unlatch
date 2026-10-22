import AppKit
import Foundation
import Testing

@testable import Unlatch

// Guards on the Sparkle keys in Resources/Info.plist.template
// (Design/sparkle-updates.md, §4) and on the Finder hand-off keys
// (Design/finder-quick-action.md, §4).

private func loadTemplate() throws -> [String: Any] {
    // Tests/UnlatchTests/<this file> -> repository root.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Resources/Info.plist.template")
    var text = try String(contentsOf: url, encoding: .utf8)
    text = text.replacingOccurrences(of: "__SHORT_VERSION__", with: "1.0.0")
    text = text.replacingOccurrences(of: "__BUILD_VERSION__", with: "1")
    let plist = try PropertyListSerialization.propertyList(
        from: Data(text.utf8), options: [], format: nil)
    return try #require(plist as? [String: Any])
}

@Test func templateFeedURLIsTheHTTPSPagesURL() throws {
    let plist = try loadTemplate()
    let feed = try #require(plist["SUFeedURL"] as? String)
    #expect(feed == "https://pablocolaiacovo.github.io/unlatch/appcast.xml")
}

@Test func templatePublicKeyIsA32ByteEd25519Key() throws {
    let plist = try loadTemplate()
    let key = try #require(plist["SUPublicEDKey"] as? String)
    // A swapped key would permanently break updates for every build shipped with it.
    #expect(key == "c1nkY1mfZROc+woQU0n8BKTxwcySykispaZaMbshWy0=")
    let data = try #require(Data(base64Encoded: key))
    #expect(data.count == 32)
}

@Test func templateDoesNotAllowAutomaticUpdates() throws {
    let plist = try loadTemplate()
    #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
}

@Test func templateChecksOnceADay() throws {
    let plist = try loadTemplate()
    #expect(plist["SUScheduledCheckInterval"] as? Int == 86400)
}

@Test func templateLeavesSparkleDefaultsAlone() throws {
    let plist = try loadTemplate()
    for key in [
        "SUEnableInstallerLauncherService", "SUEnableAutomaticChecks", "SUEnableSystemProfiling",
    ] {
        #expect(plist[key] == nil)
    }
}

@Test func templateKeepsTheMacOS14Floor() throws {
    let plist = try loadTemplate()
    #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
}

private func loadServicesEntry() throws -> [String: Any] {
    let plist = try loadTemplate()
    let services = try #require(plist["NSServices"] as? [[String: Any]])
    #expect(services.count == 1)
    return try #require(services.first)
}

@Test func templateDeclaresTheUnlockService() throws {
    let plist = try loadTemplate()
    let service = try loadServicesEntry()
    #expect(service["NSMessage"] as? String == "unlockPDFs")
    #expect(service["NSSendFileTypes"] as? [String] == ["com.adobe.pdf"])
    // Without it macOS registers the service but never shows it.
    #expect(service["NSRequiredContext"] is [String: Any])
    #expect(service["NSPortName"] as? String == plist["CFBundleName"] as? String)
    let menuItem = try #require(service["NSMenuItem"] as? [String: Any])
    let title = try #require(menuItem["default"] as? String)
    #expect(!title.isEmpty)
}

@MainActor @Test func serviceMessageMatchesTheHandoffSelector() throws {
    let service = try loadServicesEntry()
    let message = try #require(service["NSMessage"] as? String)
    // A mismatch fails silently at runtime: pbs routes to a selector that
    // doesn't exist. This test is the only guard.
    #expect(FinderHandoff.instancesRespond(to: NSSelectorFromString(message + ":userData:error:")))
}

@Test func templateDeclaresPDFAsAnAlternateDocumentType() throws {
    let plist = try loadTemplate()
    let types = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
    #expect(types.count == 1)
    let pdf = try #require(types.first)
    #expect(pdf["CFBundleTypeRole"] as? String == "Viewer")
    #expect(pdf["LSHandlerRank"] as? String == "Alternate")
    #expect(pdf["LSItemContentTypes"] as? [String] == ["com.adobe.pdf"])
}
