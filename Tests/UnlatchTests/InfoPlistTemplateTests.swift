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

// MARK: Languages (Design/spanish-localization.md §2.6)

@Test func templateDeclaresEnglishAndSpanish() throws {
    let plist = try loadTemplate()
    #expect(plist["CFBundleDevelopmentRegion"] as? String == "en")
    #expect(plist["CFBundleLocalizations"] as? [String] == ["en", "es"])
}

/// Every language the catalog translates must be declared, and every declared language must be in
/// the catalog, or the app is English on a Mac set to the one that was forgotten.
@Test func templateLocalizationsMatchTheCatalog() throws {
    let plist = try loadTemplate()
    let declared = try #require(plist["CFBundleLocalizations"] as? [String])
    let url = repositoryRoot().appendingPathComponent(
        "Sources/Unlatch/Resources/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let catalog = try #require(json as? [String: Any])
    var languages: Set<String> = [try #require(catalog["sourceLanguage"] as? String)]
    let strings = try #require(catalog["strings"] as? [String: [String: Any]])
    for entry in strings.values {
        languages.formUnion((entry["localizations"] as? [String: Any])?.keys.map { $0 } ?? [])
    }
    #expect(Set(declared) == languages)
}

/// macOS localizes a Services menu title from `ServicesMenu.strings` in the app bundle's
/// `<lang>.lproj`, keyed by the English `default` title (Apple QA1605). It never reads the
/// resource bundle that `Bundle.module` points at, so the file lives under Resources/ and
/// Scripts/package-app.sh copies it into Contents/Resources.
@Test func servicesMenuTitleIsTranslatedForEveryDeclaredLanguage() throws {
    let plist = try loadTemplate()
    let service = try loadServicesEntry()
    let menuItem = try #require(service["NSMenuItem"] as? [String: Any])
    let title = try #require(menuItem["default"] as? String)
    let declared = try #require(plist["CFBundleLocalizations"] as? [String])
    for language in declared where language != "en" {
        let url = repositoryRoot().appendingPathComponent(
            "Resources/\(language).lproj/ServicesMenu.strings")
        let data = try Data(contentsOf: url)
        let table = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: String])
        #expect(Set(table.keys) == [title], "\(language): the key must be the template's default title")
        let translated = try #require(table[title])
        #expect(!translated.isEmpty)
        #expect(translated != title)
    }
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
