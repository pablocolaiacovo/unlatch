# Spanish localization (issue #86)

Issue: #86, "Show the app in Spanish when macOS is set to Spanish" (`enhancement`, `area:app`,
`area:release`, milestone v1.3).

Everything marked "observed" in this document was checked on the toolchain this repository uses:
macOS 27.0.1 (26A434), Xcode 27.0, Swift 6.4, `swift build` with its default build system
(`swiftbuild`, see `.build/.buildSystem_debug`), `swift-tools-version: 6.3`. The checks used a
throwaway package in a scratch directory, not this repository. The maintainer's Mac runs with
`AppleLanguages = ("es-AR")`, which matters for §2.7.

## 1. Summary

The `Unlatch` app gets a string catalog, `Sources/Unlatch/Resources/Localizable.xcstrings`, with
English as the source language and one neutral Spanish (`es`) translation. Swift Build compiles the
catalog into `en.lproj` and `es.lproj` inside the target's resource bundle, `UnlatchCore_Unlatch.bundle`.
`Scripts/package-app.sh` copies that bundle into `Unlatch.app/Contents/Resources`, and
`Resources/Info.plist.template` declares `CFBundleLocalizations = (en, es)`. With those in place, macOS
picks the language: Spanish when Spanish comes first among the languages the app supports, including
the per-app language in System Settings, and English otherwise. Every user-facing string in
`Sources/Unlatch` becomes a `LocalizedStringResource` from the app's bundle. `Logic.swift` returns
resources instead of `String`s, so tests can resolve them in `en` and `es` explicitly, and SwiftUI
resolves them in the view's locale.

### Goals

- Package manifest: `defaultLocalization: "en"`, plus `resources: [.process("Resources")]` on the
  `Unlatch` target.
- Every user-facing string is localized. That covers popover steps, buttons, row notes, header and done
  counts, destination options and hints, footer, ellipsis menu items and their help text, status item
  tooltip and accessibility value, the open panel's prompt, and the hidden main menu (§2.9).
- Plurals and interpolated counts and file names go through the catalog, never through English word
  surgery like `"file" : "files"`.
- `Info.plist.template` declares `CFBundleDevelopmentRegion = en` and `CFBundleLocalizations = (en,
  es)`, and `InfoPlistTemplateTests` checks both.
- Tests resolve `Logic.swift` strings in both `en` and `es` on any Mac, whatever its language.
- English snapshot references stay byte-identical. Spanish snapshot cases are added (§2.8).
- Side effect, intended: Sparkle's own windows, and AppKit's open panel, also switch to Spanish
  (§2.6).

### Non-goals (explicitly out of scope)

- Languages other than English and Spanish. Regional variants (`es-MX`, `es-ES`, `es-419`) all get the
  one `es` table.
- An in-app language setting.
- Localizing `README.md`, release notes, the Sparkle feed, or Sparkle's own UI (it ships its own
  `es.lproj`).
- Anything in `UnlatchCore`. It stays string-free (§2.5).
- Translating the output file name suffix `-unlocked` (open question 1).
- Localized `Info.plist` values through `InfoPlist.strings`. The display name stays "Unlatch", and
  `NSHumanReadableCopyright` is only shown in Finder's Get Info. `CFBundleTypeName` ("PDF Document")
  is not shown for a PDF, because Finder takes the kind from the `com.adobe.pdf` type. The one
  Info.plist value users do see, the Services menu title, is localized (§2.9.1).

## 2. Design

### 2.1 Decision 1: a string catalog, compiled by Swift Build

**Recommendation: `Localizable.xcstrings`.** Do not hand-write `.strings` or `.stringsdict` files.

What was observed with `swift build`, using the default `swiftbuild` build system and no Xcode
project. The test package had `defaultLocalization: "en"`, an `executableTarget` with
`resources: [.process("Resources")]`, and a `Resources/Localizable.xcstrings` file with an `es`
string, an `en` and `es` plural, and an interpolated `%@`:

```
.build/debug/Demo_Demo.bundle/Contents/Info.plist                    CFBundleDevelopmentRegion = en, CFBundlePackageType = BNDL
.build/debug/Demo_Demo.bundle/Contents/Resources/en.lproj/Localizable.stringsdict
.build/debug/Demo_Demo.bundle/Contents/Resources/es.lproj/Localizable.strings
.build/debug/Demo_Demo.bundle/Contents/Resources/es.lproj/Localizable.stringsdict
```

- The catalog is compiled, not copied. Plurals become `.stringsdict` with `NSStringPluralRuleType`.
  English gets no `.strings` file when every English value equals its key, which is correct, because
  lookups fall back to the key. Multi-argument plurals also compile and resolve: `"%lld saved, %lld
  failed"` with per-argument substitutions gave "1 guardado, 3 fallaron" and "5 guardados, 2
  fallaron".
- The bundle is a real macOS bundle (`Contents/Info.plist`, `Contents/Resources`). Debug builds
  ad-hoc sign it. In release builds it is not signed at all.
- `swift build -c release --arch arm64 --arch x86_64`, which is exactly what `package-app.sh` runs,
  puts the bundle at `.build/release/<Package>_<Target>.bundle`. `.build/release` is a symlink to
  `out/Products/Release`.
- **The deprecated `--build-system native` does not compile it.** That build system copies the raw
  `Localizable.xcstrings` into a flat bundle with no `.lproj`, so the app would silently stay in
  English. Its accessor also looks in different places (§2.3). The design therefore depends on Swift
  Build. §2.3 makes `package-app.sh` pin it, and a unit test catches a raw catalog (§4).

Why a catalog wins over `.strings` and `.stringsdict`:

- One file holds both languages, plural variations, per-argument substitutions, translator comments,
  and a translation state per string. That state lets a test check that every string is translated
  (§4).
- The compiler emits `.stringsdata` for every `LocalizedStringResource(...)`, `String(localized:)`,
  and SwiftUI literal key. `xcrun xcstringstool sync` merges those into the catalog, adding new keys
  and marking removed ones stale. Observed: sync works only when the catalog file is named after its
  table (`Localizable.xcstrings`). A copy under another name gets every key marked stale. The
  lightweight `xcstringstool extract` does not see SwiftUI literals, so sync must use the compiler's
  `.stringsdata`, which lives at
  `.build/out/Intermediates.noindex/UnlatchCore.build/<Config>/Unlatch-p.build/Objects-normal/<arch>/*.stringsdata`.
  §2.10 turns this into a script and a CI check.
- The `.strings` route needs a separate `.stringsdict` for every plural, hand-kept in step with the
  code, and there is no tool to tell you a key is missing.

The catalog is plain JSON and is edited by hand or with `xcstringstool`. Xcode's catalog editor also
opens it if the maintainer wants it, but the build never needs Xcode.

### 2.2 Decision 2: `LocalizedStringResource` everywhere, with an explicit bundle

#### Which bundle

The strings live in the module bundle (`Bundle.module`), not in `Bundle.main`. That is true under
`swift run`, in tests, and inside `Unlatch.app`, where `Bundle.main` is the app and `Bundle.module`
is `Contents/Resources/UnlatchCore_Unlatch.bundle`. Every lookup must name the module bundle. A lookup
without it goes to `Bundle.main`, finds nothing, and quietly shows the English key. Observed: the
compiler extracts `Text("…")` written without `bundle:` into `.stringsdata` like any other key, so
sync cannot catch the omission. §4's lint test does.

One spelling for the bundle, in a new file `Sources/Unlatch/Localization.swift`:

```swift
import Foundation

extension LocalizedStringResource.BundleDescription {
    /// The app's resource bundle (`UnlatchCore_Unlatch.bundle`), which holds the compiled
    /// Localizable.xcstrings. Every LocalizedStringResource in this target passes
    /// `bundle: .unlatch`; the default `.main` finds no strings.
    static var unlatch: Self { .atURL(Bundle.module.bundleURL) }
}

/// Text shown exactly as given: file names, paths, the app name. Resolves through the
/// catalog's "%@" entry, which is marked Don't Translate, so nothing is ever looked up for
/// the text itself. Lets functions that sometimes return a path and sometimes a sentence
/// return one type.
func verbatim(_ text: String) -> LocalizedStringResource {
    LocalizedStringResource(
        "\(text)", bundle: .unlatch,
        comment: "A file name or path shown as is. Do not translate.")
}
```

`Bundle.module` is generated as `static nonisolated let` (observed), so `.unlatch` is safe from any
isolation domain. `LocalizedStringResource` and `BundleDescription` are `Sendable`.

#### Which API

| Option | What was observed | Verdict |
| --- | --- | --- |
| `String(localized: "…", bundle: .module)` returning `String` | Correct in production. **Its `locale:` parameter does not choose the language**: `String(localized: "Saved", bundle: b, locale: Locale(identifier: "es"))` returned "Saved" in a process whose language was English. Tests could get Spanish only by loading `es.lproj` as its own `Bundle`. | Use only at AppKit call sites, as `String(localized: resource)`. |
| `LocalizedStringResource` returned from `Logic.swift`, resolved late | Setting `resource.locale = Locale(identifier: "es")` and calling `String(localized: resource)` gives Spanish, plurals included ("1 archivo guardado"), in any process. `es_AR`, `es-AR`, `es-MX`, `es-419`, and `es_ES` all select `es`, and `de` and `pt-BR` fall back to English. `Text(resource)` follows `.environment(\.locale, …)`. `Equatable` (it compares interpolated arguments) and `Sendable`, but not `Hashable`. | **Chosen.** |
| SwiftUI `Text("…", bundle: .module)` literals in views | Works, and follows `.environment(\.locale, …)`. But `Button`, `Toggle`, `.help`, and `.accessibilityLabel` have no `bundle:` parameter, so views would need two spellings. | Not used. Views take resources (below). |

So the rule for `Sources/Unlatch` is this. **Every user-facing string is a `LocalizedStringResource`
created with `bundle: .unlatch`, or is built by `verbatim(_:)`.** SwiftUI shows it with `Text(_:)`,
`Button(_:action:)`, `Toggle(_:isOn:)`, `.help(_:)`, or `.accessibilityLabel(_:)`. All of these have
`LocalizedStringResource` overloads that type-check at `-target arm64-apple-macos14.0` (observed). The
exception is `TextField(_: LocalizedStringResource, text:)`, which is macOS 26 only, so the password
fields use `SecureField(text:prompt:label:)` and `TextField(text:prompt:label:)`, both macOS 12+. AppKit
gets `String(localized: resource)`.

**The `Locale.current` trap.** In production, never set `resource.locale` and never pass a locale
built from `Locale.current`. Leave the default. Observed:

- The default (`Locale.current` as given) resolves through the bundle's preferred localization, which
  follows the app's language. That is right in the app.
- `Locale.autoupdatingCurrent`, or `Locale(identifier: Locale.current.identifier)`, selects by the
  raw system language instead. In the test runner on the maintainer's Mac, `Locale.current` reports
  `es_AR` while the app's language resolves to English. A copied locale gave "archivos guardados"
  there, and the default gave "files saved".

Code that copies the current locale would therefore pass on CI (English runner) and fail on the
maintainer's Mac, or the other way round. Only tests set `locale`, and always to a literal `en` or
`es`.

#### Static labels

View labels with no logic live in `Localization.swift` as `enum Strings`, so translator comments sit
in one place and views read `Button(Strings.cancel) { model.reset() }`:

```swift
enum Strings {
    static let cancel = LocalizedStringResource(
        "Cancel", bundle: .unlatch, comment: "Button: abandon this batch and return to the start.")
    static let choosePDFs = LocalizedStringResource(
        "Choose PDFs…", bundle: .unlatch, comment: "Idle step: the big button that opens the file picker.")
    // … one per row of the §2.9 table marked "Strings"
}
```

`static let` of a `Sendable` type is fine under Swift 6 strict concurrency. These must be literal
initializer calls, not a wrapper function: the compiler extracts keys only from the real
`LocalizedStringResource` initializers (observed in `.stringsdata`).

#### Changed signatures in `Logic.swift`

Return types change from `String` to `LocalizedStringResource`. Parameters stay the same. The changes
are:

```swift
extension DestinationOption { var label: LocalizedStringResource { get } }
extension SaveFailure       { var note: LocalizedStringResource { get } }

func headerNote(fileCount: Int) -> LocalizedStringResource
func passwordTitle(encryptedCount: Int) -> LocalizedStringResource
func passwordSubtitle(encrypted: [LoadedFile]) -> LocalizedStringResource
func doneTitle(savedCount: Int, failedCount: Int = 0) -> LocalizedStringResource
func doneSummary(destinations: [URL], option: DestinationOption) -> LocalizedStringResource?   // nil replaces ""
func destinationHint(option: DestinationOption, sample: URL?, desktopFolder: URL, chosenFolder: URL?) -> LocalizedStringResource
func versionLabel(version: String?, build: String?) -> LocalizedStringResource
/// New: the destination step's question. The count is not shown, so the code picks a key.
func destinationQuestion(usableCount: Int) -> LocalizedStringResource

struct RowInfo: Equatable, Sendable {
    let badge: String                    // "!", "i", "✓", "•": glyphs, not words; unchanged
    let tone: RowTone
    let note: LocalizedStringResource
}

struct StatusItemPresentation: Equatable, Sendable {
    let symbolName: String
    let showsUpdateBadge: Bool
    let accessibilityValue: LocalizedStringResource?
    let toolTip: LocalizedStringResource
    static let accessibilityLabel = "Unlatch"                         // String: the app name, never translated
    static let updateAvailableValue: LocalizedStringResource          // "Update available"
    static let updateAvailableToolTip: LocalizedStringResource        // "Unlatch: update available"
}

struct LoginItemControl: Equatable, Sendable { let isOn: Bool; let isEnabled: Bool; let help: LocalizedStringResource }
struct UpdateFooterPresentation: Equatable, Sendable {
    let menuItemTitle: LocalizedStringResource?
    let menuItemEnabled: Bool
    let showsUpdateIndicator: Bool
    static let checkTitle: LocalizedStringResource                    // "Check for Updates…"
    static let updateAvailableTitle: LocalizedStringResource          // "Update Available…"
}
struct AutomaticChecksMenuItem: Equatable, Sendable {
    let title: LocalizedStringResource
    let isChecked: Bool
    static let checkAutomaticallyTitle: LocalizedStringResource       // "Check Automatically"
}
```

`AppModel`: `headerText` becomes `LocalizedStringResource`, and `savedTo: String` becomes
`savedTo: LocalizedStringResource?` (`nil` for nothing saved; `DoneStepView` tests `!= nil` instead of
`!isEmpty`). `PopoverView.versionText` becomes a resource. `FooterButton.title` becomes
`LocalizedStringResource`.

#### Plurals and interpolation rules

1. A count that is shown goes into the key as an interpolation, `"\(count) files"`, which the
   catalog sees as `%lld files`. The catalog carries plural variations wherever a language needs
   them. Spanish needs some where English does not. For example, `"%lld saved, %lld failed"` must
   agree in Spanish ("1 guardado" against "2 guardados"), so it gets per-argument substitutions in
   `es` while staying a plain string in `en`.
2. The code branches on a count only where the sentences differ in meaning, or where the count is not
   shown. Those are: 0 files gives "Remove PDF passwords". One encrypted file gives "This PDF needs a
   password". One saved file gives "Saved". One failure gives "Couldn't save — the file failed". And
   `destinationQuestion` picks "…the unlocked file go?" or "…the unlocked files go?". These branches
   already exist; each branch gets its own key.
3. The current `Text("Where should the unlocked \(… ? "files" : "file") go?")` interpolates an
   English word into a sentence, so the key becomes `%@` with "file" inside it, and that cannot be
   translated. It is replaced by `destinationQuestion(usableCount:)` (rule 2).
4. File names and paths are interpolated as `String` (`%@`) and never looked up. Path-only results
   use `verbatim(_:)`. Observed: a `%` in a file name ("a 100%.pdf", "Résumé %d.pdf") passes through
   untouched.
5. `"\(dir)/ (originals replaced)"` keeps the path as an argument, so Spanish can reorder it.
   `dir + "/…-unlocked.pdf"` and `dir + "/"` are paths, so they use `verbatim`. The `-unlocked`
   suffix is the real file name the app writes (open question 1).

#### Concurrency

Nothing new crosses an isolation boundary. `Logic.swift` stays nonisolated and pure, and its new
return types are `Sendable` value types. `AppModel.save()` builds `savedTo` on the main actor, as it
does today, after the detached task returns, and only `Sendable` outcomes cross back. Views and
`StatusItemController` resolve resources on the main actor. `String(localized:)` and bundle lookups
are thread-safe.

### 2.3 Decision 3: getting the bundle into `Unlatch.app`, and finding it at runtime

#### How `Bundle.module` finds the bundle (observed: generated `resource_bundle_accessor.swift`)

Under Swift Build the generated accessor tries these locations in order and takes the first that
loads. **It has no fallback to an absolute `.build` path.**

1. `PACKAGE_RESOURCE_BUNDLE_PATH` from the environment, Debug builds only.
2. `Bundle.main.resourceURL/UnlatchCore_Unlatch.bundle`, which is **`Unlatch.app/Contents/Resources/`** in
   the app.
3. `Bundle(for: BundleFinder.self).resourceURL/…`, which is the test bundle under `swift test`
   (observed: `…/Debug/DemoTests.xctest/Contents/Resources/Demo_Demo.bundle`).
4. `Bundle.main.bundleURL/…`, which is next to the executable under `swift run`.
5. Otherwise `fatalError("unable to find bundle named UnlatchCore_Unlatch")`.

Consequences, all observed with a test app assembled the way `package-app.sh` assembles
`Unlatch.app`:

| Layout | Result |
| --- | --- |
| Bundle copied with `ditto` to `Contents/Resources/UnlatchCore_Unlatch.bundle` | Found. `codesign --verify --deep --strict` passes whether or not the nested bundle is signed. Survives the `ditto -c -k` zip round trip. |
| Bundle missing | **The app crashes on first string lookup**, which is at launch: `Fatal error: unable to find bundle named …`, exit 133. On the build machine nothing hides this, because there is no build-path fallback. |
| Bundle at the `.app` root (`Unlatch.app/UnlatchCore_Unlatch.bundle`), where the native build system's accessor looks | `codesign --strict` fails: "unsealed contents present in the bundle root". |

So `Contents/Resources` is the only workable location, and it requires Swift Build.

#### What `devops` changes in `Scripts/package-app.sh` (task D1)

1. Pin the build system: `swift build -c release --product "$APP_NAME" --arch arm64 --arch x86_64
   --build-system swiftbuild`. The `--build-system swiftbuild` flag is a no-op today because
   swiftbuild is the default (`swift build --help`: "swiftbuild - Swift Build build engine
   (default)"). It stops a future default change, or an older toolchain, from silently producing an
   English-only bundle.
2. After copying the binary, copy the bundle the same way the script handles Sparkle, conditionally,
   so D1 can merge before the `Unlatch` target has resources:

   ```bash
   RESOURCE_BUNDLE_SRC="$REPO_ROOT/.build/release/${PACKAGE_NAME}_${APP_NAME}.bundle"
   if [[ -d "$RESOURCE_BUNDLE_SRC" ]]; then
       echo "==> Embedding ${PACKAGE_NAME}_${APP_NAME}.bundle"
       RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Resources/${PACKAGE_NAME}_${APP_NAME}.bundle"
       ditto "$RESOURCE_BUNDLE_SRC" "$RESOURCE_BUNDLE"
       # A raw catalog means the native build system ran: the app would be English-only.
       [[ -f "$RESOURCE_BUNDLE/Contents/Resources/es.lproj/Localizable.strings" ]] \
           || { echo "error: $RESOURCE_BUNDLE has no compiled es.lproj (was it built with --build-system swiftbuild?)" >&2; exit 1; }
   fi
   ```

   The bundle is named `<package>_<target>` (observed: package `Pkg`, target `Demo` gives
   `Pkg_Demo.bundle`, and the accessor's `bundleName` matches). This package is named `UnlatchCore`,
   so the `Unlatch` target's bundle is **`UnlatchCore_Unlatch.bundle`**, consistent with the existing
   `UnlatchCore_UnlatchCoreTests.bundle`. The snippet uses `PACKAGE_NAME="UnlatchCore"`, defined
   next to `APP_NAME`, with a comment that it must match `name:` in `Package.swift`. Renaming the
   package renames the bundle. The accessor follows automatically, but the script does not.
3. Signing: sign the nested bundle inside-out before the app, using the one `CODESIGN_ARGS` list
   (`sign "$RESOURCE_BUNDLE"`). It contains no Mach-O, and the app's resource seal would cover it
   anyway (observed: unsigned, it still verifies `--deep --strict`). Signing it keeps the "every
   nested bundle signed with the same identity" rule simple when #8 switches to Developer ID. With
   `--options runtime --timestamp` added later, nothing changes for a bundle without code.
   Notarization accepts resource bundles in `Contents/Resources`. This is an assumption to recheck
   when #8 lands, because nothing here is notarized yet.
4. No change to `CFBundleLocalizations` handling in the script. It comes from the template (§2.6).

Nothing changes for `swift run`: the bundle sits next to the executable in `.build/debug`. Nor for
`swift test`: Swift Build copies it into `UnlatchTests.xctest/Contents/Resources` (observed for the
test package).

### 2.4 `swift run` shows English

Observed: a bare executable has no `Info.plist`, so `Bundle.main` has no localizations, and the
resource bundle follows the main bundle's language. Under `swift run` the app is English even on a
Spanish Mac, and `-AppleLanguages '(es)'` does not change that. This is expected, not a bug.
Developers see Spanish through the packaged app, the Spanish snapshot references, and the Spanish
`Logic` tests.

The alternative was rejected but verified. Embedding a two-key plist (`CFBundleDevelopmentRegion`,
`CFBundleLocalizations`) into the binary with `-Xlinker -sectcreate -Xlinker __TEXT -Xlinker
__info_plist -Xlinker <path>` makes `swift run` follow the system language. Tests were unaffected and
the signed `.app` still verified. It costs a second plist to keep in step with the template, plus
another `unsafeFlags` entry whose path handling under Swift Build was only checked with an absolute
path. That is not worth it for a developer convenience. If the maintainer wants it later, it is a
self-contained follow-up.

### 2.5 Decision 4: `UnlatchCore` text never reaches users

`UnlatchCore` has two public types. `Classification` has no strings. `UnlockError` (`wrongPassword`,
`unreadable`, `writeFailed`) does not conform to `LocalizedError` and carries no message. The app
already maps every outcome to its own text: `FileKind(classification)` feeds `rowInfo`,
`SaveFailure(UnlockError)` feeds `SaveFailure.note`, and `FileManager` errors become `.copyFailed`.
The doc comment on `SaveFailure.note` already rules out showing `localizedDescription`. The only
places raw errors appear are `NSLog` calls (`AppModel.setLaunchAtLogin`), which go to Console, not to
users, and stay English.

**Recommendation: no change to `UnlatchCore`.** Keep it string-free, with no `LocalizedError`
conformance, no catalog, and no `defaultLocalization` effect. `UnlatchCore` has no resources, so the
package-level `defaultLocalization` does nothing to it. Any future user-facing failure gets a new
`UnlockError` case, mapped in `SaveFailure` in the app, and localized there. That is the pattern that
already exists, so this design adds nothing new to the core.

### 2.6 Decision 5: `Info.plist.template`

Add, next to `CFBundleName`:

```xml
<!-- The languages the app ships (Sources/Unlatch/Resources/Localizable.xcstrings). macOS
     picks the app's language from this list: without it the app is English even on a
     Spanish Mac, and System Settings offers no per-app language. Keep it in step with the
     catalog (InfoPlistTemplateTests checks both). -->
<key>CFBundleDevelopmentRegion</key>
<string>en</string>
<key>CFBundleLocalizations</key>
<array>
    <string>en</string>
    <string>es</string>
</array>
```

Why this is required, observed with two test apps that differed only in this key. The system
language was `es-AR`, and the resource bundle was in `Contents/Resources` in both:

| App | `Bundle.module.preferredLocalizations` | Lookup |
| --- | --- | --- |
| No `CFBundleLocalizations` | `["en"]` | "Saved" (English on a Spanish Mac) |
| `CFBundleLocalizations = (en, es)` | `["es"]` | "Guardado", "3 archivos guardados", "Guardado en a.pdf" |
| … with `-AppleLanguages '(de)'` | `["en"]` | "Saved" (unsupported language falls back to English) |
| … with `-AppleLanguages '(fr, es)'` | `["es"]` | "Guardado" (first supported language wins) |
| … with `defaults write <bundle id> AppleLanguages '(en)'` (what the per-app setting writes) | `["en"]` | "Saved" |

A resource bundle follows the main bundle's chosen language. The main bundle has no `.lproj`
directories (the strings live in the nested bundle), so `CFBundleLocalizations` is the only thing
that tells macOS which languages the app supports.

Side effects:

- **Sparkle.** Sparkle 2.10.0 ships `es.lproj` (observed in `.build/release/Sparkle.framework`).
  Today Sparkle's update window is English on a Spanish Mac, for the same reason. After this change it
  is Spanish. Its wording ("Comprobar automáticamente", informal "tú") is a useful reference for ours
  (open question 2).
- **AppKit.** `NSOpenPanel`'s own buttons and sidebar follow the app's language, so they also become
  Spanish.
- **Partial-state risk.** Declaring `es` before all strings are translated would ship a mixed UI,
  with Spanish system panels and English app text. The template change therefore lands in the same PR
  as the last string conversion (T2, §5).

The per-app language list in System Settings > General > Language & Region > Applications is
populated by LaunchServices from the app's declared localizations. This was not observed, because it
needs a registered app and the GUI. It is manual check M3. Fallback if Unlatch is not offered there:
devops adds `en.lproj` and `es.lproj` directories, each holding an empty `InfoPlist.strings`, to
`Contents/Resources`.

`InfoPlistTemplateTests` gains two tests:

- `templateDeclaresEnglishAndSpanish`: `CFBundleDevelopmentRegion == "en"` and
  `CFBundleLocalizations == ["en", "es"]`.
- `templateLocalizationsMatchTheCatalog`: parse `Sources/Unlatch/Resources/Localizable.xcstrings`
  via `#filePath`, as `loadTemplate()` does. The catalog's `sourceLanguage` plus every language that
  appears under any `localizations` must equal the set in `CFBundleLocalizations`. This catches a
  language added to one but not the other.

### 2.7 Decision 6: deterministic tests in `en` and `es`

Observed in `swift test`, debug and release. The test runner's main bundle is SwiftPM's helper under
`…/usr/libexec/swift/pm`, and it has no localizations. So a resource resolved with the default locale
is **English on every Mac, including the maintainer's `es-AR` Mac**, even though `Locale.current`
reports `es_AR` there. `Bundle.module` resolves to the copy inside `UnlatchTests.xctest`.

A new `Tests/UnlatchTests/LocalizationSupport.swift` adds one helper used by all tests:

```swift
/// Resolves `resource` in `language` ("en" or "es"), independent of this Mac's language.
func resolved(_ resource: LocalizedStringResource, _ language: String) -> String {
    var resource = resource
    resource.locale = Locale(identifier: language)
    return String(localized: resource)
}
func en(_ resource: LocalizedStringResource) -> String { resolved(resource, "en") }
func es(_ resource: LocalizedStringResource) -> String { resolved(resource, "es") }
```

Existing English assertions become, for example, `#expect(en(headerNote(fileCount: 0)) == "Remove
PDF passwords")`. They pin English explicitly instead of relying on the runner having no language.
Struct comparisons such as `#expect(info == RowInfo(badge: "•", tone: .neutral, note: "Password
protected"))` change to compare `info.badge`, `info.tone`, and `en(info.note)` separately. Two
resources compare equal only if they have the same key, arguments, bundle, and locale, so comparing
against a literal is brittle.

Details in §4.

### 2.8 Spanish snapshot cases

**Recommendation: add them**, inside the existing `PopoverSnapshotTests` suite so that
`record-snapshots.yml`'s `--filter PopoverSnapshotTests` records them with no workflow change.

Plumbing, with English unchanged:

- `PopoverHostingController.init(model:updater:locale: Locale? = nil)` passes it to `PopoverView`,
  which gains `var locale: Locale? = nil` and applies
  `.transformEnvironment(\.locale) { if let locale { $0 = locale } }` on its root. With `nil`
  (production, and every existing English test) the environment is untouched, so the English render
  tree is the same code path as today. Observed: `Text(resource)` follows `\.locale` ("Saved" 38 pt
  wide with `en` or no override, and 60 pt with `es`, which equals `Text(verbatim: "Guardado")`).
- `renderPopover(_:updater:appearance:locale:)` and `assertPopoverSnapshot(…, locale:)` gain the same
  optional parameter and pass it through.
- New tests:
  `@Test(arguments: PopoverFixture.allCases) func popoverSpanish(_ fixture:)` with
  `named: "\(fixture.rawValue)-es"`, and a debug-only `footerUpdateAvailableSpanish`. That adds 14
  references, `popover.<name>-es-<appearance>.png`. The fixtures stay as they are, English file
  names included: they are data, not UI.
- Because `Logic.swift` returns resources that the views resolve, every popover string follows the
  environment, including `savedTo`, which the fixtures build with `doneSummary`. Strings resolved in
  AppKit (tooltip, menus, open panel) are not in the render, so this needs no extra plumbing.

Why add them: they are the only automated check that Spanish fits the fixed 372 pt popover (§2.11).
They catch a later English copy edit or layout change that clips Spanish. They also give the
maintainer a reviewable image of every Spanish step without changing the Mac's language. The cost is
14 more CI-recorded PNGs to review whenever the layout changes on purpose, using the same flow B as
today. English references must not change. If T2's CI run reports any English mismatch, that is a
bug in the conversion, not a reason to re-record.

The `RECORDED_ON.txt` fingerprint does not need a language field: English cases render English on
any runner (§2.7), and Spanish cases set `es` explicitly.

### 2.9 Decision 7: inventory of user-facing strings in `Sources/Unlatch`

"Kind" is where the string appears. "P/I" means plural (P) or interpolation (I). "Goes to" is
`Logic` (a function in `Logic.swift`), `Strings` (a static in `Localization.swift`), or `verbatim`
(never translated).

| File | String (English, as today) | Kind | P/I | Goes to |
| --- | --- | --- | --- | --- |
| Logic.swift | Same folder, add “-unlocked” | radio label | — | Logic `DestinationOption.label` |
| Logic.swift | Same folder, replace original | radio label | — | Logic |
| Logic.swift | Desktop | radio label | — | Logic |
| Logic.swift | Choose folder… | radio label | — | Logic |
| Logic.swift | Password didn’t match — not saved | row note | — | Logic `SaveFailure.note` |
| Logic.swift | Couldn’t be read — not saved | row note | — | Logic |
| Logic.swift | Couldn’t write the file — not saved | row note | — | Logic |
| Logic.swift | Couldn’t be copied — not saved | row note | — | Logic |
| Logic.swift | Remove PDF passwords | header note | — | Logic `headerNote` |
| Logic.swift | 1 file / N files | header note | P | Logic, one key `%lld files` with plural variations |
| Logic.swift | This PDF needs a password | step title | — | Logic `passwordTitle` |
| Logic.swift | N files need a password (N > 1) | step title | P | Logic `%lld files need a password` |
| Logic.swift | We’ll try the same password on all of them. Anything that doesn’t match gets skipped. | step subtitle | — | Logic `passwordSubtitle` |
| Logic.swift | (single file) the file name | step subtitle | I | verbatim |
| Logic.swift | Couldn’t save — nothing was written | done title | — | Logic `doneTitle` |
| Logic.swift | Saved | done title | — | Logic |
| Logic.swift | N files saved (N > 1) | done title | P | Logic |
| Logic.swift | Couldn’t save — the file failed | done title | — | Logic |
| Logic.swift | Couldn’t save — all N files failed | done title | P | Logic |
| Logic.swift | N saved, M failed | done title | P×2 | Logic, per-argument substitutions in `es` |
| Logic.swift | (single file) path | done summary | I | verbatim |
| Logic.swift | N files in M folders | done summary | P×2 | Logic |
| Logic.swift | `<dir>`/…-unlocked.pdf | done summary | I | verbatim (real file name pattern) |
| Logic.swift | `<dir>`/ (originals replaced) | done summary | I | Logic `%@/ (originals replaced)` |
| Logic.swift | `<dir>`/ | done summary | I | verbatim |
| Logic.swift | next to the original | destination hint | — | Logic `destinationHint` |
| Logic.swift | overwrites the original | destination hint | — | Logic |
| Logic.swift | opens a save panel | destination hint | — | Logic |
| Logic.swift | paths (sample, desktop, chosen folder) | destination hint | I | verbatim |
| Logic.swift | Version X / Version X (B) / Version dev | menu item (disabled) | I | Logic `Version %@`, `Version %@ (%@)`; "dev" stays as is |
| Logic.swift | Not a readable PDF — skipped | row note | — | Logic `rowInfo` |
| Logic.swift | Copied as-is — opens without a password | row note | — | Logic |
| Logic.swift | No open password — permissions only | row note | — | Logic |
| Logic.swift | Not encrypted — copied as-is | row note | — | Logic |
| Logic.swift | Not encrypted — nothing to unlock | row note | — | Logic |
| Logic.swift | Unlocked | row note | — | Logic |
| Logic.swift | Password protected | row note | — | Logic |
| Logic.swift | ! i ✓ • | row badge glyph | — | stays `String`, not localized |
| Logic.swift | Unlatch | status item accessibility label, tooltip | — | stays `String` / verbatim (app name) |
| Logic.swift | Update available | status item accessibility value | — | Logic `StatusItemPresentation` |
| Logic.swift | Unlatch: update available | status item tooltip | — | Logic |
| Logic.swift | Unlatch opens when you log in | menu item help | — | Logic `loginItemControl` |
| Logic.swift | Open Unlatch when you log in | menu item help | — | Logic |
| Logic.swift | Turned off in System Settings > General > Login Items. Check to open Login Items and allow Unlatch. | menu item help | — | Logic (names a macOS pane: open question 3) |
| Logic.swift | Available when Unlatch runs from an app bundle | menu item help | — | Logic |
| Logic.swift | Check for Updates… | menu item | — | Logic `UpdateFooterPresentation` |
| Logic.swift | Update Available… | menu item | — | Logic |
| Logic.swift | Check Automatically | menu item | — | Logic `AutomaticChecksMenuItem` |
| AppModel.swift | Choose | `NSOpenPanel.prompt` (folder picker) | — | Strings, `String(localized:)` |
| AppModel.swift | NSLog messages | Console only | I | not localized |
| AppDelegate.swift | Quit Unlatch | main menu item | — | Strings, `String(localized:)` |
| AppDelegate.swift | Edit, Undo, Redo, Cut, Copy, Paste, Select All | main menu (hidden, see below) | — | Strings, `String(localized:)` |
| StatusItemController.swift | (renders `StatusItemPresentation`) | tooltip, accessibility | — | `String(localized:)` at render |
| Views/IdleStepView.swift | Choose PDFs… | button | — | Strings |
| Views/IdleStepView.swift | Removes the open password so the file opens without one. Nothing leaves your Mac. | caption | — | Strings |
| Views/PasswordStepView.swift | Show / Hide | button | — | Strings (today a `String` ternary, so it is not even looked up) |
| Views/PasswordStepView.swift | Password | field placeholder ×2 | — | Strings, `SecureField`/`TextField(text:prompt:label:)` |
| Views/PasswordStepView.swift | That password didn’t work. Try again. | inline error | — | Strings |
| Views/PasswordStepView.swift | Cancel, Unlock | buttons | — | Strings |
| Views/DestinationStepView.swift | Where should the unlocked file/files go? | step title | P (code-picked) | Logic `destinationQuestion` |
| Views/DestinationStepView.swift | Cancel, Save | buttons | — | Strings |
| Views/DoneStepView.swift | Show in Finder, Done | buttons | — | Strings |
| Views/FileRowList.swift | file name | row title | — | `Text(String)`, verbatim already; unchanged |
| Views/PopoverView.swift | Unlatch | header | — | `Text(verbatim:)` (app name) |
| Views/PopoverView.swift | Open at Login | menu toggle | — | Strings |
| Views/PopoverView.swift | More | ellipsis help + accessibility label | — | Strings |
| Views/PopoverView.swift | Update available | ellipsis accessibility value | — | Logic `StatusItemPresentation.updateAvailableValue` (same text, one key) |
| Views/PopoverView.swift | Update Available | footer button title + accessibility label | — | Strings |
| Views/PopoverView.swift | See the available update | footer button help | — | Strings |
| Views/PopoverView.swift | Quit | footer button | — | Strings |
| Views/PopoverView.swift | Quit Unlatch | footer help + accessibility label | — | Strings (same key as the main menu item) |
| Views/PopoverView.swift | Unlocking… | working step | — | Strings |
| FinderHandoff.swift | Unlatch couldn't read the selected files. | Services error text | — | Strings, `String(localized:)` (§2.9.1) |
| Info.plist.template | Unlock with Unlatch | Services menu title | — | `Resources/es.lproj/ServicesMenu.strings`, not the catalog (§2.9.1) |

`AppUpdater.swift`, `LoginItem.swift`, `PopoverDismissalMonitor.swift`, and
`PopoverHostingController.swift` have no user-facing strings. Sparkle's windows and alerts come from
Sparkle's bundle. `SMAppService`'s "Login Item Added" notification comes from the system.

The main menu (`AppDelegate.makeMainMenu`) is not visible, because `LSUIElement` apps get no menu
bar. Only its key equivalents matter. It is localized anyway, since that is cheap: eight strings with
standard Spanish translations. That leaves no English string reachable through Accessibility.

Some example translations, for direction only. The maintainer, a native speaker, decides all wording
(open question 2):

| English | Spanish (draft) |
| --- | --- |
| Choose PDFs… | Elegir PDF… |
| Unlock | Desbloquear |
| `%lld files` (one / other) | %lld archivo / %lld archivos |
| `%lld saved, %lld failed` | `%#@saved@, %#@failed@` with "%arg guardado / guardados", "%arg falló / fallaron" |
| Check Automatically | Comprobar automáticamente (Sparkle's own `es` wording) |

### 2.9.1 Finder quick action strings (#93, #96)

The Finder hand-off added two user-facing strings and one Info.plist value that looks like one.

- **Services error text.** `FinderHandoff.unlockPDFs` sets `error.pointee` when the pasteboard holds
  no file URL. macOS shows that text, so it goes through the catalog:
  `String(localized: Strings.finderCouldntReadFiles)`. The English text is unchanged, apostrophe
  included.
- **Services menu title.** `NSServices > NSMenuItem > default = "Unlock with Unlatch"` is read by
  `pbs`, not by `Bundle.module`, so the catalog cannot translate it. Apple's QA1605 describes the
  mechanism, and `pbs` itself references a `ServicesMenu` table: a `ServicesMenu.strings` file in the
  app bundle's `<lang>.lproj`, keyed by the English `default` text, with the translation as the value.
  If there is no match, the English title shows. It lives in the repository at
  `Resources/es.lproj/ServicesMenu.strings` ("Desbloquear con Unlatch"), next to the template that
  holds the key. `Scripts/package-app.sh` must copy it to `Unlatch.app/Contents/Resources/es.lproj/`
  before the app is signed (task D3 below). `InfoPlistTemplateTests` checks that the file exists for
  every declared language and that its only key is the template's title, so a reworded title cannot
  silently drop the translation.
- **Everything else.** `CFBundleTypeName` is not shown for PDFs (see the non-goals). `NSPortName` is
  an identifier. `FinderHandoff` and `AppModel` have no alert, panel message, or accessibility text
  beyond what §2.9 already lists. `NSLog` lines stay English.

A side effect worth knowing: once `Contents/Resources/es.lproj` exists in the app, the main bundle has
a real `.lproj` too, which is also the fallback for M3 in §2.6.

### 2.10 Keeping the catalog in step with the code

`Scripts/sync-strings.sh` (devops, D1) runs `swift build --build-system swiftbuild` (debug). It then
collects
`.build/out/Intermediates.noindex/*/Debug/Unlatch-p.build/Objects-normal/*/*.stringsdata`, excluding
the `-testable-` variant, and fails if none are found, because the path is a Swift Build internal and
may move. Finally it runs `xcrun xcstringstool sync Sources/Unlatch/Resources/Localizable.xcstrings
--stringsdata <files>`. Developers run it after adding or changing a string, translate the new
entries, and commit the catalog.

D2 adds a CI step after "Build": run the script, then `git diff --exit-code --
Sources/Unlatch/Resources/Localizable.xcstrings`. That fails when the code has a key the catalog lacks,
or the catalog has an entry the code no longer uses. Prerequisite to verify in D2: running sync twice
on a committed catalog gives no diff. That holds if the catalog was last written by `xcstringstool` in
its own JSON formatting, so T1 must commit a catalog produced by the script, not hand-formatted JSON.

### 2.11 Decision 8: Spanish in the fixed-width popover

The popover is 372 pt wide with 14 pt padding, so text gets about 344 pt, or about 322 pt beside a
radio or a row badge. Spanish usually runs 15 to 30% longer than English. Risk ranking:

| Risk | Where | Why |
| --- | --- | --- |
| High | `passwordTitle` ("N archivos necesitan una contraseña", 13 pt medium) | No `.fixedSize(horizontal: false, vertical: true)`. A second line could be clipped under `preferredContentSize` sizing (the bug `IdleStepView` documents). |
| High | Row notes in `FileRowList` (10.5 pt), e.g. "Copiado tal cual — se abre sin contraseña", "No se pudo escribir el archivo — no se guardó" | No `lineLimit` or `fixedSize`, and they sit beside the badge. These are the longest Spanish strings in a narrow column. |
| High | Destination option labels (13 pt), e.g. "Misma carpeta, reemplazar el original", "Misma carpeta, agregar “-unlocked”" | No `fixedSize`. Wrapping would clip. |
| Medium | Footer row (fixed 26 pt height): "Actualización disponible" + ellipsis + "Salir ⏻" | Single row of fixed height. Should fit, at about 150 pt of 344, but it is the only fixed-height row. |
| Medium | Done title "No se pudo guardar — fallaron los N archivos" | Has `fixedSize`, so it wraps rather than clipping, but it grows the popover. Acceptable. |
| Low | Idle caption, password subtitle, error text, destination question | Have `fixedSize` and wrap. The popover grows by a line. |
| Low | `doneSummary` "(originales reemplazados)" | Monospaced, `lineLimit(1)`, middle truncation. The path is truncated before the Spanish tail is. |
| Low | Show/Hide ("Mostrar"/"Ocultar") | Same length as each other, so the password field narrows slightly but does not jump on toggle. |
| None | Ellipsis menu items, help tooltips, status item tooltip | Native menus and tooltips size themselves. |

Approach: T2 does not change layout preemptively. T3's Spanish snapshots, plus the eye check in light
and dark (M1), decide. Where Spanish clips, the first choice is shorter wording, decided by the
maintainer. The second is adding `.fixedSize(horizontal: false, vertical: true)` to that `Text`. In
the second case, CI must show the English references unchanged. If an English reference changes,
re-record it through flow B in the same PR and say so in the PR body.

### 2.12 Edge cases

- **The system language is a regional Spanish** (`es-AR`, `es-MX`, `es-419`, `es-ES`): `es` is
  chosen (observed for all of these).
- **A language listed before Spanish that the app does not support** (`fr, es`): Spanish (observed).
  Spanish listed after English: English, which is the correct macOS behaviour.
- **The language changes while the app runs**: macOS asks the user to relaunch apps. Unlatch keeps
  its language until relaunch, like every Mac app. Nothing to handle.
- **A key is missing from `es`**: the lookup falls back to English for that string. §4's catalog test
  catches it before merge.
- **Bundle missing in a broken package**: crash at launch (§2.3). D1's assertion and manual check M2
  catch it before release.
- **A file name containing `%` or format specifiers**: shown literally (observed).
- **Plural "many" in Spanish CLDR** (millions): out of reach for file counts. The catalog can add
  the category if a translator wants it, with no code change.

## 3. Trade-offs

### 3.1 Catalog against `.strings` and `.stringsdict`

See §2.1. The catalog compiles under `swift build`, keeps plurals and comments in one file, and can be
checked by `xcstringstool sync`. `.strings` and `.stringsdict` would work too, but they double the
files and lose the missing-key check. One cost of the catalog: it depends on Swift Build. The
deprecated native build system ships it raw. That is mitigated by pinning `--build-system swiftbuild`
in packaging and by a unit test.

### 3.2 `LocalizedStringResource` against `String` returns in `Logic.swift`

Returning `String` keeps the current tests nearly untouched. But it needs a way to choose the
language in tests. `String(localized:locale:)` does not choose it (observed), so every function would
need an injected `Bundle` pointing at `es.lproj`. Spanish snapshots would also need every view to
pass a locale or bundle into every `Logic` call. Returning resources moves the language choice to the
point of display. The views follow `\.locale`, AppKit follows the app's language, and tests set
`locale`. It costs one-line test helpers and an `en(…)` wrap on existing assertions.

### 3.3 Central `Strings` enum against inline `Text("…", bundle: .module)`

Inline literals keep English next to its use. But `Button`, `Toggle`, `.help`, and
`.accessibilityLabel` cannot take a bundle with a literal, so views would mix two spellings. With one
form (resources), the lint rule in §4 is a simple text check: no string literal as the first argument
of those initializers in `Sources/Unlatch`.

### 3.4 Copying `.lproj` into `Unlatch.app/Contents/Resources` and using `Bundle.main`

This would make plain `Text("…")` work inside the app. It fails under `swift run` and in tests, where
`Bundle.main` is not the app. It would also need a second packaging step that unpacks the module
bundle. `Bundle.module` behaves the same everywhere once the bundle sits in `Contents/Resources`.
Rejected.

### 3.5 Spanish snapshots against an eye check only

An eye check covers the release, and snapshots cover every later change. 14 PNGs are a small cost
next to an unnoticed clipped row note in Spanish (§2.8).

## 4. Testing strategy

**`Tests/UnlatchTests/LogicTests.swift`, `StatusItemLogicTests.swift`, `UpdaterLogicTests.swift`, and
`LoginItemTests.swift` (always run)**

- Every existing English assertion is wrapped with `en(…)`. Its expected English text is unchanged.
- New Spanish assertions with exact expected strings, for every function that has a plural, an
  interpolation, or a code-side branch: `headerNote` (0, 1, 2), `passwordTitle` (1, 3),
  `passwordSubtitle` (one file, which returns the file name unchanged in both languages, and a batch),
  `doneTitle` (all six branches, with `(1, 1)`, `(2, 1)`, `(1, 3)` for agreement), `doneSummary` (one
  path, several folders, each option), `destinationQuestion` (1, 2), and `versionLabel`. The exact
  text is the maintainer-approved wording, and tests change with the wording, as English tests do
  today.
- A parameterized property test over the same set of outputs, for both languages: the result
  contains no unresolved specifier (`%@`, `%lld`, `%#@`), contains the interpolated file name or
  count where there is one, and, for `es`, differs from `en` except for an explicit allowlist (paths,
  "Unlatch").
- One `rowInfo` and `SaveFailure.note` test per case in `es`.

**New `Tests/UnlatchTests/LocalizationTests.swift` (always run)**

- `moduleBundleHasCompiledSpanish`: `Bundle.module.localizations` contains `en` and `es`.
  `Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil,
  localization: "es")` is non-nil, and `Bundle.module.url(forResource: "Localizable", withExtension:
  "xcstrings")` is nil. This fails if the native build system shipped the raw catalog.
- `catalogIsFullyTranslated`: parse the catalog via `#filePath`. `sourceLanguage == "en"`. Every
  entry either has `shouldTranslate == false` (only `%@`) or an `es` localization whose every
  `stringUnit`, in variations and substitutions too, has `state == "translated"`. No entry has
  `extractionState == "stale"`.
- `sourcesUseTheAppBundle` (lint): for each `.swift` file under `Sources/Unlatch`, read via
  `#filePath`:
  - The number of `LocalizedStringResource(` occurrences equals the number of `bundle: .unlatch`
    occurrences.
  - No string literal is the first argument of `Text(`, `Button(`, `Toggle(`, `Menu(`, `SecureField(`,
    `TextField(`, `Label(`, `.help(`, `.accessibilityLabel(`, `.accessibilityValue(`, `withTitle:`,
    `.toolTip =`, or `.prompt =`. A regex such as `(Text|Button|…)\(\s*"` works, and
    `Text(verbatim:` is allowed.
  - The failure message names the file and line.

  It is crude on purpose. It guards the one silent failure (§2.2) that neither the catalog sync nor
  English tests can see.

**`Tests/UnlatchTests/InfoPlistTemplateTests.swift`**: the two tests in §2.6.

**`Tests/UnlatchTests/PopoverSnapshotTests.swift` (gated, recorded by CI)**: the existing 14 English
references unchanged. Plus 14 Spanish ones in T3 (§2.8), bootstrapped through flow B in
RELEASING.md.

**Fixtures**: no PDF fixtures, and `Scripts/generate-fixtures.sh` does not change.

**Manual checks (maintainer, on a Mac, with a bundle from `Scripts/package-app.sh` copied to
`/Applications`)**

- M1. With macOS in Spanish (the maintainer's default), walk every step: idle, a password batch with
  one wrong password, destination with each option, done, a partial failure, the ellipsis menu with
  its tooltips, and the status item tooltip with an update pending, if one can be staged. Do it in
  light and dark. Nothing clips. Sparkle's "Check for Updates…" window is Spanish.
- M2. `Unlatch.app/Contents/Resources/<bundle>/Contents/Resources/es.lproj/Localizable.strings`
  exists. `codesign --verify --deep --strict --verbose=2` passes. The zipped app downloaded on a
  clean account launches without crashing.
- M3. System Settings > General > Language & Region > Applications: "+" offers Unlatch. Set it to
  English, relaunch Unlatch, and it is English. Set it back to the system default.
- M4. On an English Mac or account (or with the per-app setting at English): everything is English
  and identical to v1.2.
- M5. `swift run Unlatch` shows English (expected, §2.4).
- M6. With macOS in Spanish and the packaged app registered (copied to `/Applications` and launched
  once), select a PDF in Finder: the right-click Services (Quick Actions) list shows "Desbloquear con
  Unlatch". In English it shows "Unlock with Unlatch". `pbs -update` may be needed after the first
  launch.

## 5. Implementation plan

```
D1 (devops: package-app.sh + sync script) ──► T1 (infra + Logic.swift + tests) ──► T2 (views, AppKit, Info.plist; the user-facing PR) ──► T3 (Spanish snapshots)
                                                                                    └──► D2 (devops: CI catalog-sync check)
```

D1 must merge first. Once T1 merges, the code reads `Bundle.module` at launch. A package built
without D1 crashes at launch (§2.3). D1's copy is conditional, so it is harmless before T1.

Suggested PRs. Labels are `project-owner`'s call.

| PR | Tasks | Title (changelog line) | Labels | Body |
| --- | --- | --- | --- | --- |
| 1 | D1 | "Package the app's localized strings into Unlatch.app" | `area:release`, `skip-changelog` | Part of #86 |
| 2 | T1 | "Add an English and Spanish string catalog for the app" | `area:app`, `skip-changelog` | Part of #86 |
| 3 | T2 | **"Show the app in Spanish when macOS is set to Spanish"** | `enhancement`, `area:app` | Part of #86 (Closes #86 if T3 and D2 already merged) |
| 4 | T3 | "Snapshot the popover in Spanish" | `area:app`, `skip-changelog` | Part of #86 |
| 5 | D2 | "Check in CI that the string catalog matches the code" | `area:release`, `skip-changelog` | Closes #86, if last |

T1 has no user-visible effect. The strings exist, but the app stays English until T2 declares `es`
in the template.

### D1 (`devops`): Copy the resource bundle into the app, and add the sync script

- `Scripts/package-app.sh`: `--build-system swiftbuild`, the conditional `ditto` into
  `Contents/Resources`, the compiled-`es.lproj` assertion, and `sign` on the nested bundle before the
  app (§2.3). Header comment: a short "Resources" paragraph beside "Sparkle".
- `Scripts/sync-strings.sh` as in §2.10. It exits non-zero with a clear message when no `.stringsdata`
  is found or the catalog does not exist yet ("nothing to sync before T1").

Acceptance criteria:

- On `main` today, before T1, the script output is unchanged except the build-system flag, and
  `dist/Unlatch.app` verifies `--deep --strict`.
- On a scratch branch with an `Unlatch` target resource and a one-string catalog, not merged:
  `dist/Unlatch.app/Contents/Resources/<bundle>/Contents/Resources/es.lproj/Localizable.strings`
  exists, `codesign --verify --deep --strict` passes, and the app launches. The bundle is
  `UnlatchCore_Unlatch.bundle`.
- `shellcheck` is clean for both scripts.

### T1 (`macos-developer`): String catalog, `Logic.swift` resources, and tests

Depends on D1 merged.

- `Package.swift`: `defaultLocalization: "en"` on the package and
  `resources: [.process("Resources")]` on `Unlatch`, each with a one-line comment.
- `Sources/Unlatch/Resources/Localizable.xcstrings`, generated by `Scripts/sync-strings.sh`, then
  filled in. Every `Logic.swift` string gets `es` and the plural variations and substitutions from
  §2.2. Draft translations, marked "for maintainer review" in the PR body. The `%@` entry gets
  `shouldTranslate: false`.
- `Sources/Unlatch/Localization.swift`: `BundleDescription.unlatch`, `verbatim(_:)`, and `enum
  Strings`, empty or with only what T1 needs.
- `Logic.swift`: the §2.2 signature changes, `destinationQuestion(usableCount:)`, and a comment on
  every resource for translators.
- Minimal call-site updates so it compiles: views wrap in `Text(…)`/`Button(…)`/`.help(…)`,
  `StatusItemController` uses `String(localized:)`, `AppModel.savedTo` becomes optional.
- Tests: `LocalizationSupport.swift`, the `en(…)` wrap, the Spanish `Logic` cases and the property
  test (§4), and `LocalizationTests.moduleBundleHasCompiledSpanish`.

Acceptance criteria:

- `swift build` and `swift test` pass with no new warnings on the maintainer's `es-AR` Mac and in CI.
  English assertions keep their exact current text.
- The CI snapshot run shows all 14 English references unchanged. Any mismatch is a bug in this PR.
- `Scripts/sync-strings.sh` followed by `git diff` on the catalog shows nothing.
- `Sources/UnlatchCore` is untouched.

### T2 (`macos-developer`): Views, AppKit strings, and `Info.plist`

Depends on T1. This is the user-facing PR.

- Every row of §2.9 not done in T1. That covers `Strings` entries for every view label, help text, and
  accessibility label. `FooterButton.title` becomes a resource. `SecureField`/`TextField(text:prompt:label:)`
  for the password fields. "Show"/"Hide" becomes resources. The header uses `Text(verbatim: "Unlatch")`.
  `AppDelegate` menu titles and `NSOpenPanel.prompt` go through `String(localized:)`.
- Catalog: all new keys translated. `LocalizationTests.catalogIsFullyTranslated` and
  `sourcesUseTheAppBundle` added. Both must pass.
- `Resources/Info.plist.template`: §2.6 keys and comment. `InfoPlistTemplateTests`: the two new tests.
- Finder strings (§2.9.1): `Strings.finderCouldntReadFiles`, and `Resources/es.lproj/ServicesMenu.strings`
  with a test that its key matches the template. T2 does not touch `Scripts/package-app.sh`; that is D3.
- PR body: screenshots of each step in Spanish (light and dark) from the packaged app, plus the
  results of M1 to M4.

Acceptance criteria:

- `swift build` and `swift test` are clean. English snapshot references are unchanged in CI.
- `dist/Unlatch.app` from `Scripts/package-app.sh` shows Spanish on the maintainer's Mac and English
  with the per-app language set to English (M1, M3, M4). Sparkle's window is Spanish.
- `grep -rn 'Text("' Sources/Unlatch` finds no string literal key, and the lint test agrees.

### T3 (`macos-developer`): Spanish snapshot cases

Depends on T2 (the strings must be final enough to record).

- `PopoverHostingController`/`PopoverView` `locale` plumbing, plus the `renderPopover` and
  `assertPopoverSnapshot` parameter (§2.8).
- `popoverSpanish(_:)` and the debug-only `footerUpdateAvailableSpanish()`. Bootstrap the 14 references
  through flow B. Inspect each by eye; this is the human sign-off on fit. Where Spanish clips, apply
  §2.11's order of fixes.
- RELEASING.md "Snapshot tests" first paragraph: add "and each of them in Spanish". `macos-developer`
  drafts it in this PR, as decided for #28, and `project-owner` reviews.

Acceptance criteria:

- `__Snapshots__/PopoverSnapshotTests/` holds 28 PNGs. The 14 English ones are byte-identical to
  `main` (`git diff --stat` lists only additions).
- CI is green, including on "Re-run all jobs".

### D3 (`devops`): Package the Services menu translation

Depends on T2's `Resources/es.lproj/ServicesMenu.strings`. In `Scripts/package-app.sh`, after the
Info.plist and icon steps and before `sign "$APP_BUNDLE"`:

```bash
# Services menu title (Resources/es.lproj/ServicesMenu.strings): macOS reads it from the app
# bundle's own lproj, not from the module resource bundle.
for LPROJ in "$REPO_ROOT"/Resources/*.lproj; do
    [[ -d "$LPROJ" ]] && ditto "$LPROJ" "$APP_BUNDLE/Contents/Resources/$(basename "$LPROJ")"
done
```

No separate signing step: the files are plain resources, and the app's signature seals
`Contents/Resources`. Verified in a throwaway copy of `dist/Unlatch.app` with the directory added and
the app re-signed: `codesign --verify --deep --strict` passes. Ship D3 with or right after T2, or the
Services entry stays English on a Spanish Mac while the rest of the app is Spanish.

### D2 (`devops`): CI catalog-sync check

Depends on T2.

- `ci.yml`, after "Build": run `Scripts/sync-strings.sh`, then `git diff --exit-code --
  Sources/Unlatch/Resources/Localizable.xcstrings`, with a failure message telling the author to run
  the script and translate the new entries.

Acceptance criteria:

- Green on `main` after T2. On a scratch branch that adds `Text(Strings.x)` with a new resource and no
  catalog change, the step fails and names the catalog. The job name stays `build-and-test`.
- Running the script twice locally produces no diff (§2.10 prerequisite).

## 6. Open questions

**Resolved by the maintainer on 2026-10-21:** all three questions are accepted as recommended
("Go with the recommended approach"). `-unlocked` stays in every language, Spanish uses informal
"tú", and the login item help text does not name the System Settings pane.

1. **Resolved 2026-10-21 (was `needs-decision`): Does the "add suffix" option write `-unlocked` in Spanish too?** Today
   `destinationURL` always appends `-unlocked`, and the option label quotes it. Translating the suffix
   ("-desbloqueado") would make output file names depend on the UI language. That would break anyone's
   scripts or habits across machines and widen the change into `destinationURL` and its tests.
   **Recommendation: keep `-unlocked` in every language**, and quote it literally in the Spanish label
   ("Misma carpeta, agregar “-unlocked”").
2. **Resolved 2026-10-21 (was `needs-decision`): Spanish register and vocabulary.** Neutral `es` must read well in Spain and
   Latin America. **Recommendation: informal "tú"**, which macOS's own Spanish uses, as does
   Sparkle's `es` ("Siempre puedes buscar actualizaciones…"). Prefer vocabulary that is neutral across
   regions ("archivo", "carpeta", "contraseña"). The maintainer reviews every string in T1 and T2,
   and tests and snapshots follow the approved wording.
3. **Resolved 2026-10-21 (was `needs-decision`): How the login item help text names System Settings.** macOS calls the app
   "Ajustes del Sistema" in `es` and, as far as can be told without a Latin American Spanish Mac at
   hand, "Configuración del Sistema" in `es-419`. Our one `es` table serves both. **Recommendation:
   phrase it without naming the pane path**, for example "Desactivado en los ajustes de inicio de
   sesión de macOS. Marca la opción para abrirlos y permitir Unlatch." That reads correctly in every
   variant. Alternatively use the `es` (Spain) names, which `es-419` users would see slightly off.
