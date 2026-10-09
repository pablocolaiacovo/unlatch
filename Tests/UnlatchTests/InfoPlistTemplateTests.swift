import Foundation
import Testing

// Guards on the Sparkle keys in Resources/Info.plist.template
// (Design/sparkle-updates.md, §4).

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
    let url = try #require(URL(string: feed))
    #expect(url.scheme == "https")
    #expect(url.host == "pablocolaiacovo.github.io")
    #expect(url.lastPathComponent == "appcast.xml")
}

@Test func templatePublicKeyIsA32ByteEd25519Key() throws {
    let plist = try loadTemplate()
    let key = try #require(plist["SUPublicEDKey"] as? String)
    let data = try #require(Data(base64Encoded: key))
    #expect(data.count == 32)
}

@Test func templateDoesNotAllowAutomaticUpdates() throws {
    let plist = try loadTemplate()
    #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
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
