import Foundation
import Testing
@testable import Unlatch

// The compiled string catalog (Design/spanish-localization.md §2.1, §4).

/// Swift Build compiles `Localizable.xcstrings` into one `.lproj` per language. The deprecated
/// native build system copies the raw catalog instead, which would leave the app English-only
/// without any other sign, so this fails if that ever ships.
@Test func moduleBundleHasCompiledSpanish() {
    let bundle = Bundle.module
    #expect(bundle.localizations.contains("en"))
    #expect(bundle.localizations.contains("es"))
    #expect(
        bundle.url(
            forResource: "Localizable", withExtension: "strings", subdirectory: nil,
            localization: "es") != nil)
    #expect(bundle.url(forResource: "Localizable", withExtension: "xcstrings") == nil)
}

// MARK: The catalog

private func loadCatalog() throws -> [String: Any] {
    let url = repositoryRoot().appendingPathComponent(
        "Sources/Unlatch/Resources/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return try #require(json as? [String: Any])
}

/// Every `stringUnit` below `node`, at any depth: plain values, plural and device variations, and
/// per-argument substitutions all nest them.
private func stringUnits(in node: Any) -> [[String: Any]] {
    if let dict = node as? [String: Any] {
        var found: [[String: Any]] = []
        if let unit = dict["stringUnit"] as? [String: Any] { found.append(unit) }
        for (key, value) in dict where key != "stringUnit" { found += stringUnits(in: value) }
        return found
    }
    if let array = node as? [Any] { return array.flatMap(stringUnits(in:)) }
    return []
}

/// The `es` half of a catalog entry, or nil when there is none.
private func spanish(of entry: [String: Any]) -> [String: Any]? {
    (entry["localizations"] as? [String: Any])?["es"] as? [String: Any]
}

/// A key that is missing from `es` silently falls back to English, so this is the only thing
/// between an untranslated string and a mixed-language popover.
@Test func catalogIsFullyTranslated() throws {
    let catalog = try loadCatalog()
    #expect(catalog["sourceLanguage"] as? String == "en")
    let strings = try #require(catalog["strings"] as? [String: [String: Any]])
    #expect(!strings.isEmpty)
    for (key, entry) in strings.sorted(by: { $0.key < $1.key }) {
        #expect(
            entry["extractionState"] as? String != "stale",
            "'\(key)' is stale: no code uses it. Run Scripts/sync-strings.sh and delete it.")
        if entry["shouldTranslate"] as? Bool == false { continue }
        guard let es = spanish(of: entry) else {
            Issue.record("'\(key)' has no Spanish translation")
            continue
        }
        let units = stringUnits(in: es)
        #expect(!units.isEmpty, "'\(key)' has an empty Spanish entry")
        for unit in units {
            #expect(
                unit["state"] as? String == "translated",
                "'\(key)' has a Spanish value that is not translated: \(unit["value"] ?? "nil")")
            #expect(!((unit["value"] as? String) ?? "").isEmpty, "'\(key)' has an empty value")
        }
    }
}

// MARK: Every string goes through the app's bundle

/// What is wrong with one Swift source, as "line N: message" strings. Comments are ignored.
/// Crude on purpose: it guards the one silent failure (Design/spanish-localization.md §2.2), a
/// lookup that skips the app's resource bundle and quietly shows the English key.
func localizationViolations(in source: String) -> [String] {
    var violations: [String] = []
    var resources = 0
    var bundles = 0
    // A string literal as the first argument of a view or AppKit initializer, which would look
    // itself up in Bundle.main. `Text(verbatim:` is not matched, since "verbatim" is no quote.
    let literalKey = try? NSRegularExpression(
        pattern: [
            #"\b(Text|Button|Toggle|Menu|SecureField|TextField|Label|NSMenu|NSMenuItem)\(\s*(title:\s*)?""#,
            #"\.(help|accessibilityLabel|accessibilityValue)\(\s*""#,
            #"setAccessibility(Label|Value)\(\s*""#,
            #"withTitle:\s*""#,
            #"\.(toolTip|prompt|title|message|informativeText|messageText)\s*=\s*""#,
            #"error\.pointee\s*=\s*""#,
        ].joined(separator: "|"))
    for (index, line) in source.components(separatedBy: "\n").enumerated() {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
        resources += line.components(separatedBy: "LocalizedStringResource(").count - 1
        bundles += line.components(separatedBy: "bundle: .unlatch").count - 1
        if literalKey?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
            violations.append(
                "line \(index + 1): a string literal is used as a localization key; use a Strings entry")
        }
    }
    if resources != bundles {
        violations.append(
            "\(resources) LocalizedStringResource( initializers but \(bundles) 'bundle: .unlatch'")
    }
    return violations
}

@Test func sourcesUseTheAppBundle() throws {
    let sources = repositoryRoot().appendingPathComponent("Sources/Unlatch")
    let files = try #require(
        FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var checked = 0
    for case let url as URL in files where url.pathExtension == "swift" {
        checked += 1
        let source = try String(contentsOf: url, encoding: .utf8)
        for violation in localizationViolations(in: source) {
            Issue.record("\(url.lastPathComponent) \(violation)")
        }
    }
    #expect(checked > 10)
}

@Test func localizationLintCatchesTheMistakesItIsFor() {
    let bad = [
        #"Text("Cancel")"#,
        #"Button("Cancel") { }"#,
        #"Toggle("Open at Login", isOn: $on)"#,
        #"SecureField("Password", text: $text)"#,
        #"    .help("More")"#,
        #"    .accessibilityLabel("More")"#,
        #"panel.prompt = "Choose""#,
        #"button.toolTip = "Unlatch""#,
        #"NSMenu(title: "Edit")"#,
        #"menu.addItem(withTitle: "Undo", action: nil, keyEquivalent: "z")"#,
        #"error.pointee = "Nope" as NSString"#,
        #"let x = LocalizedStringResource("Saved", comment: "No bundle.")"#,
    ]
    for line in bad {
        #expect(!localizationViolations(in: line).isEmpty, "not caught: \(line)")
    }
    let good = [
        #"Text(verbatim: "Unlatch")"#,
        "Text(Strings.cancel)",
        "Button(Strings.cancel) { }",
        "SecureField(text: $text, prompt: Text(Strings.password)) { Text(Strings.password) }",
        "panel.prompt = String(localized: Strings.chooseFolderPrompt)",
        #"let x = LocalizedStringResource("Saved", bundle: .unlatch, comment: "Fine.")"#,
        #"// Text("Cancel") in a comment"#,
    ]
    for line in good {
        #expect(localizationViolations(in: line).isEmpty, "wrongly flagged: \(line)")
    }
}
