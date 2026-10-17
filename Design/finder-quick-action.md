# Unlock PDFs from Finder (issue #14)

Issue: #14, "Unlock PDFs from a Finder Quick Action" (`enhancement`, `area:app`, milestone v1.2).
The maintainer's comments on the issue frame it:

- Dropping PDFs on the menu bar icon is not viable (#15), so a Finder entry is the planned
  Finder-integrated way into Unlatch.
- On 2026-10-09 the issue moved from v1.1 to v1.2. It needs this design first, and its last
  checkbox asks for verification "from a signed, notarized bundle", which looks like a dependency on
  #8 (Developer ID). #8 is deferred in Backlog behind a paid membership.

This design finds that the recommended mechanism does **not** need #8, an app extension, an Xcode
project, entitlements, or any change to the signing order in `Scripts/package-app.sh`. A true
Quick Action app extension does need more, and it is deferred (§3.2).

## 1. Summary

Right-click one or more PDFs in Finder and choose **Unlock with Unlatch**. Unlatch launches if it
isn't running, its popover opens under the menu bar icon, and the selected files go through the
existing flow: `AppModel.load(_:)`, then the password step, then the destination step. The entry is
a Services menu item declared in `Info.plist` (`NSServices`) and served by a small provider object in
the app. The same hand-off also accepts files from **Open With > Unlatch** and `open -a Unlatch
file.pdf`, because the app declares PDF as a document type at `Alternate` rank. It never becomes the
default PDF viewer. Everything works with today's ad-hoc signed, non-sandboxed bundle.

### Goals

1. A Finder context-menu entry for PDFs, for one or many files, that hands the selection to the
   running app. If the app isn't running, invoking the entry launches it.
2. One entry point into the existing flow: every outside source ends in `AppModel.load(_:)`. No
   second password or destination UI.
3. Files that arrive while Unlatch is busy (a password check or save is running, or an `NSOpenPanel`
   is up) are held and loaded when that work finishes, never mixed into the in-flight batch.
4. No new bundle, executable, entitlement, or nested code signature. `Scripts/package-app.sh`, its
   inside-out signing from PR #52, and the release workflow's signature checks stay valid
   unchanged.
5. The issue's registration check becomes concrete and runnable under ad-hoc signing: a headless CI
   check (`pbs -read_bundle`) plus a clean-machine check in the beta smoke test.

### Non-goals

- A Finder Sync extension or a Finder toolbar item (out of scope in the issue).
- A Quick Action **app extension** (`.appex`, `com.apple.services`). It is buildable from SwiftPM
  (§2.8), but it must be sandboxed, and under ad-hoc signing its behaviour across updates and on a
  clean machine is unproven. It is deferred to a follow-up gated on #8 (§3.2, Open question 1).
- An Automator or Shortcuts Quick Action shipped with or installed by the app (§3.1).
- A custom URL scheme (§3.1).
- Unlocking directly from Finder without the popover, for example a "use the last password"
  shortcut. The popover flow is the product.
- Changes to `UnlatchCore`. Nothing in this design touches `Sources/UnlatchCore` or its tests.
- Drag onto the menu bar icon (#15) or keeping the popover open during a Finder drag (#30).

## 2. Design

### 2.1 Module and file map

| File | Change | Owner |
| --- | --- | --- |
| `Sources/Unlatch/Logic.swift` | Add `IncomingFiles`, `ExternalOpenAction`, `externalOpenAction(step:isPresentingPanel:)` | `macos-developer` |
| `Sources/Unlatch/AppModel.swift` | Add `openFromOutside(_:)`, `resumeExternalOpen()`, `isPresentingPanel`, and the held-files buffer. Call `resumeExternalOpen()` where work ends | `macos-developer` |
| `Sources/Unlatch/FinderHandoff.swift` | New: the Services provider, the cold-launch buffer, and burst coalescing | `macos-developer` |
| `Sources/Unlatch/AppDelegate.swift` | Own a `FinderHandoff`, set `NSApp.servicesProvider`, forward `application(_:open:)` | `macos-developer` |
| `Resources/Info.plist.template` | Add `NSServices` and `CFBundleDocumentTypes` | `macos-developer` |
| `Tests/UnlatchTests/ExternalOpenTests.swift` | New: pure helpers, plus `AppModel` hold-and-resume behaviour | `macos-developer` |
| `Tests/UnlatchTests/InfoPlistTemplateTests.swift` | Extend, or create if Sparkle's T2 hasn't landed: Services and document-type guards, and the selector cross-check | `macos-developer` |
| `README.md` | "Unlocking from Finder" under "Using the app" | `macos-developer` |
| `.github/workflows/release.yml` | One step: `pbs -read_bundle` and plist assertions on the packaged app | `devops` |
| `RELEASING.md` | One line in the step 3 smoke test | `project-owner` |

`Scripts/package-app.sh` does not change. `Package.swift` does not change. `UnlatchCore`,
`StatusItemController`, `PopoverView`, and the step views do not change.

### 2.2 Info.plist additions (`Resources/Info.plist.template`)

```xml
<!-- Finder hand-off (issue #14, Design/finder-quick-action.md). A Services
     entry, not an app extension: no sandbox, no entitlements, no nested code.
     NSMessage must match FinderHandoff's @objc selector
     unlockPDFs(_:userData:error:); InfoPlistTemplateTests checks it.
     NSRequiredContext must be present, even empty, or macOS registers the
     service but never shows it. -->
<key>NSServices</key>
<array>
    <dict>
        <key>NSMenuItem</key>
        <dict>
            <key>default</key>
            <string>Unlock with Unlatch</string>
        </dict>
        <key>NSMessage</key>
        <string>unlockPDFs</string>
        <key>NSPortName</key>
        <string>Unlatch</string>
        <key>NSSendFileTypes</key>
        <array>
            <string>com.adobe.pdf</string>
        </array>
        <key>NSRequiredContext</key>
        <dict/>
    </dict>
</array>
<!-- Lists Unlatch under Finder's Open With for PDFs and routes `open -a`
     and Open With to application(_:open:). Alternate rank: Unlatch is a
     secondary handler and never becomes the default PDF viewer. -->
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>PDF Document</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.adobe.pdf</string>
        </array>
    </dict>
</array>
```

Notes:

- **`NSRequiredContext`.** Apple's Services reference says: "Always include this property, even
  when you do not require any filtering (in which case you specify an empty dictionary as the
  value). Otherwise the system registers your service, but does not automatically present it in the
  Services menu." [Services Properties]
- **`NSSendFileTypes`** takes UTIs only. The service receives a pasteboard of file URLs. Finder
  offers the entry only when the selection conforms to `com.adobe.pdf`, which is inferred and part
  of manual check 4.
- **`NSPortName`** is the app name, `Unlatch`, which equals `CFBundleName` and `CFBundleExecutable`.
  The template test pins that equality.
- **`NSIconName`, undocumented.** Automator Quick Actions are themselves `NSServices` entries
  (`NSMessage = runWorkflowAsService`) that also carry `NSIconName` and `NSBackgroundColorName`.
  Community reports say removing `NSIconName` moves a workflow from Finder's Quick Actions submenu
  to the Services section [MacScripter]. An app's entry with `NSIconName` might therefore land in
  Quick Actions. That is undocumented for apps and could not be verified here (§2.8). Spike M1
  checks it, and the key goes in only if M1 shows it works on both macOS 14 and the current macOS.
  The design does not depend on it.
- **No `NSKeyEquivalent`.** Users can assign one in System Settings > Keyboard > Keyboard
  Shortcuts > Services > Files and Folders, which is also where they can turn the entry off.

The two version placeholders are unaffected. If Sparkle's T2 has landed, its `SU*` keys sit next to
these with no interaction.

### 2.3 The hand-off: `FinderHandoff`

```swift
// Sources/Unlatch/FinderHandoff.swift
import AppKit

/// Receives PDFs from outside the popover and hands them to AppModel. There
/// are two sources: the "Unlock with Unlatch" Services entry, and Open With,
/// `open -a`, or a drop on the app's icon in Finder (forwarded by
/// AppDelegate.application(_:open:)). There is one instance, owned by
/// AppDelegate for the process lifetime.
@MainActor
final class FinderHandoff: NSObject {
    init(coalescingDelay: Duration = .milliseconds(250))

    /// Called once by AppDelegate after StatusItemController exists. Files
    /// that arrived earlier are delivered then: on a cold launch, AppKit
    /// calls application(_:open:) before applicationDidFinishLaunching
    /// (verified, §2.8).
    func connect(to deliver: @escaping @MainActor ([URL]) -> Void)

    /// Open With, `open -a`, a drop on the app icon.
    func receive(_ urls: [URL])

    /// Services entry point. The selector must match NSMessage "unlockPDFs"
    /// in Resources/Info.plist.template.
    @objc func unlockPDFs(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>)
}
```

Behaviour:

- **`unlockPDFs`** reads `pasteboard.readObjects(forClasses: [NSURL.self], options:
  [.urlReadingFileURLsOnly: true]) as? [URL] ?? []`. Finder and `NSPerformService` both put
  `public.file-url` items on it, one per file (verified). If the result is empty, it sets
  `error.pointee = "Unlatch couldn't read the selected files." as NSString` and returns. Otherwise it
  calls `receive(_:)`. It returns immediately, so the Services request never waits on PDF work.
- **`receive(_:)`** adds the URLs to an `IncomingFiles` buffer (§2.4) and restarts a coalescing
  timer: it cancels the previous `Task`, then starts `Task { try? await Task.sleep(for: delay);
  guard !Task.isCancelled else { return }; flush() }`. `flush()` does nothing until `connect` has
  run. After that it calls `deliver(buffer.take())`. The window exists because Launch Services
  does not promise one `application(_:open:)` call per user action. An Apple forum thread documents
  9 files from one Open With arriving as 5 plus 4 [Forum 120354]. Without coalescing, the second
  call would replace the first batch (`AppModel.load` is last-wins by design). 250 ms is not
  noticeable next to an app launch or a popover animation. The Services path goes through the same
  buffer for uniformity.
- **`connect(to:)`** stores `deliver` and calls `flush()` if anything is buffered.

`AppDelegate` changes:

```swift
private let finderHandoff = FinderHandoff()

func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    statusItemController = StatusItemController(model: model)
    NSApp.servicesProvider = finderHandoff
    finderHandoff.connect { [model] urls in model.openFromOutside(urls) }
}

func application(_ application: NSApplication, open urls: [URL]) {
    finderHandoff.receive(urls)
}
```

Setting `servicesProvider` in `applicationDidFinishLaunching` is enough. On a cold launch through
the Services entry, the request arrived after `didFinishLaunching` (verified). If Sparkle's T3 has
landed, these lines sit next to the updater setup. They don't interact.

### 2.4 Pure helpers (`Logic.swift`) and `AppModel`

```swift
/// Files handed to Unlatch from outside the popover, accumulated until they
/// can be loaded. Keeps file URLs only, drops duplicates by standardized
/// path, and preserves first-seen order.
struct IncomingFiles: Equatable, Sendable {
    private(set) var urls: [URL] = []
    var isEmpty: Bool { urls.isEmpty }
    mutating func add(_ new: [URL])
    /// Returns everything accumulated and empties the buffer.
    mutating func take() -> [URL]
}

/// What to do with files that arrive from outside the popover.
enum ExternalOpenAction: Equatable, Sendable {
    case loadNow
    /// A password check or save is in flight (`.working`), or an NSOpenPanel
    /// is up. Loading now would let that work's completion write into the
    /// new batch, so hold the files until it finishes.
    case holdUntilIdle
}

func externalOpenAction(step: Step, isPresentingPanel: Bool) -> ExternalOpenAction
```

Why holding is needed: `submitPassword()` and `save()` each `await` a detached task and then write
back into `files`, `step`, `savedURLs`, and `savedTo`. Today nothing can call `load(_:)` while
`step == .working`, because the working step has no controls. Finder can, so without a guard a
finished save would mark rows of the *new* batch and jump it to `.done`. The same applies to an
`NSOpenPanel`: `browse()` and `chooseOtherFolder()` run it modally, and an Apple event or Services
request can still be handled during the modal session.

`AppModel` additions:

```swift
/// True while browse() or chooseOtherFolder() runs its modal NSOpenPanel.
private(set) var isPresentingPanel = false
@ObservationIgnored private var heldExternalFiles = IncomingFiles()

/// Entry point for files from Finder. Same effect as choosing them with
/// browse(): replaces the current batch and opens the popover. Holds them
/// instead while work is in flight (externalOpenAction).
func openFromOutside(_ urls: [URL])

/// Loads held files if the model is no longer busy. Called where busy
/// periods end: after the awaits in submitPassword() and save(), and after
/// each panel closes.
func resumeExternalOpen()
```

Rules:

- **`.loadNow`**: `load(urls)`, which already calls `onLoad` and so `presentAndFocus()`.
- **`.holdUntilIdle` because of `.working`**: add to `heldExternalFiles` and call `onLoad?()` so
  the popover opens on the spinner. The user sees the request was received.
- **`.holdUntilIdle` because of a panel**: add to `heldExternalFiles` only. The panel is already in
  front.
- **`browse()`**: sets `isPresentingPanel` around `runModal()`. If the user confirms, the panel's
  selection is loaded and held files are discarded, because the panel is the action the user
  completed last. If they cancel, `resumeExternalOpen()`.
- **`chooseOtherFolder()`**: sets `isPresentingPanel` around `runModal()`, then
  `resumeExternalOpen()`.
- **End of `submitPassword()`'s and `save()`'s tasks**: `resumeExternalOpen()`, so the newest
  request wins. After a save this replaces the done step. The files were written, but the
  "Saved" confirmation for the previous batch isn't shown. That window is normally under a second,
  so this is accepted rather than queueing a second flow (§3.4).
- **Mid-flow, not busy** (`.password` with a half-typed password, `.destination`, `.done`): the new
  batch replaces the old one, the same as `load(_:)` from any source. `loadGeneration` already
  drops a stale classification.

### 2.5 Concurrency model

- `FinderHandoff`, `AppDelegate`, and `AppModel` are all `@MainActor`. AppKit calls Services
  provider methods and `application(_:open:)` on the main thread. A Swift 6 probe with the same
  shape (`@MainActor` `NSObject` with an `@objc` provider method) built without diagnostics and ran
  without an isolation trap (§2.8).
- `NSPasteboard` is not `Sendable`. It is read synchronously inside `unlockPDFs`, and only `[URL]`
  (Sendable) is kept. `IncomingFiles` and `ExternalOpenAction` are `Sendable` value types.
- The coalescing `Task` is created on the main actor and inherits its isolation. Nothing new is
  detached. Classification still runs in `load(_:)`'s existing `Task.detached`.
- No `nonisolated(unsafe)`, `@unchecked Sendable`, or `@preconcurrency` is needed.

### 2.6 Bundling and signing

The Services entry and document type are Info.plist keys served by the main executable. The bundle
gains no `Contents/PlugIns`, no helper, and no entitlements. So:

- PR #52's sequence (`CODESIGN_ARGS`, Sparkle's `Autoupdate`, then `Updater.app`, then the
  framework, then the app) is untouched, and so is the #8 seam (`--options runtime --timestamp` in
  `CODESIGN_ARGS`).
- `codesign --verify --deep --strict`, the ad-hoc and no-Authority assertions, the zip round trip,
  and the launch check in `release.yml` keep passing as they are.
- #8 changes nothing here. Services need neither a Team ID nor notarization. Under Developer ID,
  this feature should behave identically, and #8's own clean-machine check should include invoking
  the entry once (Task T4).

**If the deferred app extension is ever built** (§3.2), it would fit PR #52's order as follows.
Sign `Contents/Frameworks` items inside-out first, then `Contents/PlugIns/UnlatchQuickAction.appex`
with `sign --entitlements Resources/UnlatchQuickAction.entitlements "$EXT"` (`sign()` passes `"$@"`
through), then the app. Never use `--deep`. Under #8 the appex gets the same `CODESIGN_ARGS`, so
hardened runtime and timestamp come for free.

### 2.7 Registration under ad-hoc signing: what works and what doesn't

- **Services registration** happens through Launch Services and the pasteboard server (`pbs`). It
  is keyed by bundle path and identifier, not by Team ID. An ad-hoc signed `LSUIElement` bundle
  registered and was invoked successfully (§2.8). On a user's Mac, Launch Services registers an app
  when it is copied to `/Applications` or first launched. That is inferred from standard behaviour,
  and the clean-machine check (§4, manual check 1) confirms it.
- **Quarantine.** The service of a quarantined, never-launched copy still registered with `pbs`
  after `lsregister -f`. Quarantine doesn't block registration. Invoking the entry on a quarantined,
  never-approved copy launches the app, which hits the same Gatekeeper block as a double-click. The
  README's first-launch steps clear it once, the same as today. I didn't trigger that dialog here.
- **Updates.** An ad-hoc identity changes with every build (cdhash). Services don't care, because
  nothing about the entry is tied to the signature. Sparkle replaces the bundle at the same path,
  and Launch Services re-reads the new Info.plist. That is inferred, and it gets checked during the
  Sparkle beta upgrade if both features are in the same beta. Otherwise it's checked at the first
  v1.2 beta (§4, manual check 6).
- **Development copies.** Every launched `dist/Unlatch.app` registers too. With two copies of the
  same bundle identifier, Launch Services picks one, possibly the dev copy. This is the same name
  clash the GUI capture notes already warn about. Unregister stale copies with `lsregister -u`.
- **The app extension, for comparison.** pkd (PlugInKit) registered a hand-built, ad-hoc signed,
  sandboxed appex only after its containing app was **launched**. `lsregister -f` alone did not
  register it, with or without quarantine. The unproven parts are §3.2's risks: whether it runs
  from Finder, the sandboxed hand-off, its container across cdhash changes, and enablement in
  System Settings.

### 2.8 Verified during design (Swift 6.4, Xcode 27.0 27A266a, macOS 27.0.1, this Mac)

I checked these with throwaway bundles in `/tmp/fqa-exp`, then unregistered them and deleted them
(`pluginkit`, `pbs -dump`, and `lsregister -dump` show no leftovers). The repository was not touched,
apart from a baseline `swift build` and `swift test` on `main`, both clean.

**Verified:**

1. An ad-hoc signed (`flags=0x2(adhoc)`, `TeamIdentifier=not set`), non-sandboxed `LSUIElement`
   app with the `NSServices` entry from §2.2 shows up in `pbs -dump` after `lsregister -f` and
   `pbs -update`. It needed no entitlements.
2. `NSPerformService("Unlock with …", pasteboard)` with two PDF file URLs, while the app was **not
   running**, launched it. Order of events: `applicationWillFinishLaunching`, then
   `applicationDidFinishLaunching` (where `servicesProvider` was set), then one provider call with
   **both URLs**. A second invocation while running went to the same process.
3. `open -a <app> a.pdf b.pdf`: while running, one `application(_:open:)` call with 2 URLs. From
   cold, **`application(_:open:)` arrived before `applicationDidFinishLaunching`**. Unlatch only
   wires `StatusItemController` and `model.onLoad` in `didFinishLaunching`, so without
   `FinderHandoff`'s buffer the files would load with no popover shown.
4. The `@MainActor` delegate with an `@objc` provider method and `application(_:open:)` compiled in
   Swift 6 language mode without diagnostics and ran without an isolation trap.
5. With the `Alternate`-rank PDF document type, the app appears in
   `NSWorkspace.urlsForApplications(toOpen:)` for a PDF (Finder's Open With list), and
   `urlForApplication(toOpen: .pdf)` stays `/System/Applications/Preview.app`. Launch Services flags
   bundles under `/tmp` as `in-temp-dir` and leaves them out of Open With, so this check needs a
   non-temporary path.
6. A quarantined (`com.apple.quarantine` set), never-launched copy's service is registered by `pbs`.
7. `pbs -read_bundle <app>` prints the parsed service entries **without registering** them. It is
   usable as a CI check.
8. App extension feasibility, for §3.2:
   - An appex hand-built with `swiftc -parse-as-library -application-extension … -Xlinker -e
     -Xlinker _NSExtensionMain` (Xcode's own `LD_ENTRY_POINT` for app extensions, from
     `DarwinProductTypes.xcspec`), ad-hoc signed with `com.apple.security.app-sandbox` and
     `files.user-selected.read-only`, embedded in `Contents/PlugIns`, and signed inside-out passes
     `codesign --verify --deep --strict`.
   - pkd lists it (`pluginkit -m`) once the containing app is launched.
   - A SwiftPM `executableTarget` with those flags as `unsafeFlags` builds a universal binary with
     the `_NSExtensionMain` entry point. **No Xcode project is required** for either option.
9. `NSItemProvider.loadItem(forTypeIdentifier:options:completionHandler:)`, which the appex route
   would use, is deprecated in the macOS 27 SDK in favour of `loadObject(ofClass:)`.

**Not verified (inferred, covered by manual checks in §4):**

- **Where Finder places the entry**, in the Services section at the bottom of the context menu or
  in the Quick Actions submenu, on macOS 14 and on the current macOS, and whether `NSIconName`
  changes that. This session has no Accessibility permission (`osascript … System Events` returned
  -1719), so Finder's menus couldn't be read. Secondary sources say plain Services sit at the bottom
  of the menu, or in a Services submenu when there are more than a few, while Quick Actions has its
  own submenu [Six Colors].
- Whether Finder's multi-file Open With arrives in one `application(_:open:)` call. Coalescing
  makes the answer irrelevant.
- Whether handing files over through Services or Open With triggers a Files and Folders (TCC) prompt
  for `~/Desktop`, `~/Documents`, or `~/Downloads`, compared with choosing them in the picker.
- Registration on a clean Mac after a browser download and the README's first-launch steps.
- Whether the appex actually runs when picked in Finder, and whether a sandboxed appex can
  `NSWorkspace.open(_:withApplicationAt:)` its non-sandboxed container with the files. The
  `NSExtension` SPI host I tried crashed inside ExtensionFoundation, so this wasn't driven
  headlessly.

### 2.9 Edge cases

- **Mixed selection** (PDFs plus other files): Finder doesn't offer the Services entry, and Open
  With doesn't list Unlatch (inferred, manual check 4). Through `open -a` or Open With > Other, a
  non-PDF reaches `classify`, which reports `.unreadable` and shows the existing "Not a readable PDF
  — skipped" row.
- **Duplicates** in one hand-off or across a coalesced burst are dropped by `IncomingFiles`.
  `save()`'s comment already anticipates duplicates. This makes them unreachable from Finder.
- **Folders**: `IncomingFiles` keeps file URLs, and a folder URL is a file URL. Finder won't send
  one for a PDF-only entry. If `open -a` does, it shows as unreadable, the same as above.
- **Uppercase `.PDF`** maps to `com.adobe.pdf`. A PDF with no extension gets no entry, which is
  acceptable.
- **iCloud placeholders (dataless files)** behave as they do from the picker today.
- **Status item hidden** (menu bar overflow behind the notch, or third-party managers): the popover
  anchors to a hidden button. That's an existing limitation. It's noted for manual check 3 and not
  solved here.
- **Popover already open on another step**: replaced (§2.4). **Busy**: held, then loaded.
- **Service invoked during a Sparkle update session**: Sparkle's window is separate. The popover
  opens on top as it would from a click. Nothing special.
- **User disables the entry** in System Settings > Keyboard > Keyboard Shortcuts > Services: Open
  With still works. The README mentions both.
- **`swift run Unlatch`**: no bundle, so no Services entry or Open With. `open -a` doesn't apply.
  The code paths are inert, and unit tests cover the logic.

## 3. Trade-offs

### 3.1 The four mechanisms

| | Services entry (`NSServices`) | Action extension (`.appex`) | Automator / Shortcuts Quick Action | URL scheme, `open -a`, Open With |
| --- | --- | --- | --- | --- |
| Buildable from SwiftPM plus `package-app.sh` | Yes: Info.plist plus code | Yes, but a second executable target with `unsafeFlags`, its own Info.plist and entitlements, and assembly into `Contents/PlugIns` (§2.8) | The workflow is authored once in Automator's GUI and committed as a bundle. Shortcuts files must be signed with `shortcuts sign`, which needs the maintainer's iCloud account | Yes: Info.plist only |
| Sandbox and entitlements | None | **App Sandbox required** for macOS app extensions [Quinn, DTS], plus user-selected file access | None (runs in Automator's runner) | None |
| Registration under ad-hoc | `pbs`, keyed by path and bundle ID. Verified | pkd registers after the app is launched. Verified locally, unproven on a clean machine | The user, or the app, must put it in `~/Library/Services`, outside the bundle | Launch Services. Verified |
| Launches the app when not running | Yes. Verified | The extension runs on its own and must launch the app itself (`NSWorkspace.open`). Unverified from a sandbox | Yes, via "Open Finder Items with Unlatch" (inferred) | Yes. Verified (`open -a`) |
| Multiple PDFs | One pasteboard with all URLs. Verified | One request with N attachments | Yes | Possibly split across calls [Forum 120354], so coalesce |
| Where it shows in Finder | Services section or submenu. Quick Actions possibly with `NSIconName` (spike M1) | **Quick Actions submenu and Preview pane** (`NSExtensionServiceAllowsFinderPreviewItem`) | Quick Actions submenu and Preview pane | Open With submenu only |
| Lifecycle | Removed with the app | Removed with the app | **Orphaned** in `~/Library/Services` when the app is deleted. Version drift | Removed with the app |

**Chosen: a Services entry plus Open With, both feeding one hand-off.** It is the only option that
meets every scope item under the current ad-hoc distribution, with no new build product, no
sandbox, and no signing change. Open With costs one plist block and gives a second Finder route that
survives if the user disables the Service.

Rejected:

- **Automator Quick Action.** It's the cheapest way to get a literal "Quick Actions" entry, but
  shipping it means writing into the user's `~/Library/Services` from the app (or asking them to
  double-click an installer). The entry outlives the app, nothing removes it on uninstall, and
  Automator is in maintenance mode. **Shortcuts** can't be installed without user import and an
  iCloud-signed file. App Intents would need Xcode's metadata extraction step, which SwiftPM
  doesn't run.
- **URL scheme** (`unlatch://open?path=…`): Finder has no way to invoke it, so it would still need
  one of the other options to call it. It also lets any web page make Unlatch load an arbitrary
  local path into the popover. `NSWorkspace.open(_:withApplicationAt:)` is the better transport if
  an extension ever needs one.

### 3.2 Services now, the Quick Action extension later

The issue title says "Quick Action", and only an Action extension (or a workflow) is guaranteed to
appear in Finder's Quick Actions submenu and the Preview pane. An extension costs:

- A second SwiftPM executable target with `unsafeFlags` for the entry point and
  `-application-extension`, plus a `--product` build in `package-app.sh`.
- Its own Info.plist template and an entitlements file, and assembly into `Contents/PlugIns` with
  entitlement-preserving inside-out signing.
- A **sandboxed** process that has to hand files to a non-sandboxed app. This is unverified.
- On macOS 14+, a container whose access is tied to the code identity. Under ad-hoc signing that
  identity is the cdhash, which changes with every update. That risks data-protection prompts or a
  fresh container per update (inferred, untested). It goes away with #8's stable Team ID.
- Possibly a manual enable in System Settings' Finder extensions list, which pkd's default
  (unelected) state suggests.

None of that serves the user better than "Unlock with Unlatch" in the context menu, which the
Services entry already gives. **Recommendation:** ship Services and Open With in v1.2, and track the
extension as a Backlog follow-up that depends on #8. That issue would reuse `FinderHandoff.receive`
unchanged. If spike M1 shows that `NSIconName` already puts the Services entry under Quick Actions,
the follow-up may not be needed at all. Open question 1.

### 3.3 Declaring PDF as a document type

The risk would be Unlatch becoming the default PDF app. With `LSHandlerRank = Alternate` it
doesn't: Preview stayed default (verified). Apple defines Alternate as a secondary viewer
[LS release notes]. The cost is one more line in every PDF's Open With menu, which is product
surface. Open question 2.

### 3.4 Newest request wins, versus queueing batches

Queueing would preserve every done screen, but it needs a visible queue ("2 more batches waiting")
and turns a single-batch popover into a multi-batch one. Newest-wins matches what `load(_:)`
already does for the picker, and only the narrow `.working` window needs holding. **Newest wins.**

### 3.5 No Xcode project

The issue's "depends on #7" note expected an extension to force an Xcode project. Neither the chosen
design nor the deferred extension needs one (§2.8). SwiftPM stays the only build system.

## 4. Testing strategy

### Unit tests (`Tests/UnlatchTests`)

`ExternalOpenTests.swift`:

- `IncomingFiles`:
  - It keeps order.
  - It drops a duplicate given as `/a/../a/x.pdf` versus `/a/x.pdf` (standardized).
  - It drops non-file URLs (`https://…`).
  - `take()` returns everything and empties the buffer.
  - Adding after `take()` starts fresh.
- `externalOpenAction`:
  - `.working` gives `.holdUntilIdle`.
  - Every other `Step` with `isPresentingPanel == false` gives `.loadNow`.
  - Any step with `isPresentingPanel == true` gives `.holdUntilIdle`.
- `AppModel`, with the existing fake `LoginItemService`, and without fixtures. `load(_:)` calls
  `onLoad` synchronously, so counting `onLoad` calls observes it without awaiting classification.
  - From `.idle`, `openFromOutside([u])` calls `onLoad` once.
  - With `step = .working`, `openFromOutside([u])` calls `onLoad` once (the popover opens on the
    spinner), leaves `files` unchanged, and holds `u`.
  - Setting `step = .password` and then calling `resumeExternalOpen()` loads, so `onLoad` fires
    again. A second `resumeExternalOpen()` does nothing.
  - `openFromOutside([])` does nothing.

`InfoPlistTemplateTests.swift`. Extend Sparkle T2's file if it exists. Otherwise create it with the
same approach: read the template via `#filePath`, substitute the two placeholders, and parse with
`PropertyListSerialization`.

- `NSServices` has exactly one entry, with:
  - `NSMessage == "unlockPDFs"`.
  - `NSSendFileTypes == ["com.adobe.pdf"]`.
  - `NSRequiredContext` present as a dictionary.
  - `NSPortName == CFBundleName`.
  - A non-empty `NSMenuItem.default`.
- **Selector cross-check** (`@MainActor`):
  `FinderHandoff.instancesRespond(to: NSSelectorFromString(message + ":userData:error:"))`. A
  mismatch fails silently at runtime, because `pbs` happily routes to a selector that doesn't
  exist, so this test is the only guard.
- `CFBundleDocumentTypes` has one PDF entry: role `Viewer`, rank `Alternate`, and `LSItemContentTypes
  == ["com.adobe.pdf"]`.

`FinderHandoff`'s timer isn't unit-tested. Its logic is `IncomingFiles` plus one `Task.sleep`, and
manual check 2 covers it. `Tests/UnlatchCoreTests`, the fixtures, and `Scripts/generate-fixtures.sh`
don't change.

### CI (`devops`, `release.yml` `build-and-package`)

A "Verify Finder hand-off" step after "Verify signature":

- `pbs -read_bundle dist/Unlatch.app` output contains `NSMessage = unlockPDFs`,
  `NSPortName = Unlatch`, and `com.adobe.pdf`. Capture it into a variable and then grep (no `pbs |
  grep -q` under pipefail, as PR #52 learned).
- PlistBuddy: `:CFBundleDocumentTypes:0:LSHandlerRank` is `Alternate`.
- `dist/Unlatch.app/Contents/PlugIns` does not exist. This guards the "no nested code" assumption
  this design relies on, so a later extension has to update this step on purpose.

### Manual checks (maintainer, GUI)

Run these on a `Scripts/package-app.sh` build copied to `/Applications` and launched once. Quit any
other copy first and `lsregister -u` stale `dist/` copies. This throwaway client drives the entry
without the GUI, for checks 2 and 5:

```swift
// perform.swift, built with: swiftc perform.swift -o perform. Not committed.
import AppKit
let urls = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: $0) as NSURL }
let pb = NSPasteboard(name: .init("unlatch-service-test"))
pb.clearContents(); pb.writeObjects(urls)
print(NSPerformService(CommandLine.arguments[1], pb))   // "Unlock with Unlatch"
```

1. **Placement (spike M1, before T2 merges).** Right-click a PDF in Finder on macOS 14 and on the
   current macOS. Record where "Unlock with Unlatch" appears: the bottom of the menu, a Services
   submenu, or Quick Actions. Repeat with `NSIconName = NSActionTemplate` added to the entry
   (rebuild, `/System/Library/CoreServices/pbs -update`, relaunch Finder with `killall Finder`).
   Attach screenshots to #14.
2. **Cold launch.** Quit Unlatch. Select three PDFs (one password-protected, one owner-restricted,
   one damaged) and choose the entry. Unlatch launches, the popover opens under the icon with three
   rows, and it goes to the password step.
3. **Warm and mid-flow.** Repeat with the popover closed, then open on the destination step. The new
   batch replaces the old. Start a save of a large PDF and invoke the entry during the spinner: the
   new batch loads when the save finishes.
4. **Selection rules.** With a PDF plus a `.txt` selected, the entry and Open With > Unlatch don't
   appear. Open With > Unlatch on two PDFs gives one batch of two. Preview stays the default for
   double-click.
5. **Panel open.** Click "Choose PDFs…" and, while the panel is up, run `perform` from Terminal.
   Cancel the panel and the held files load. Repeat and confirm the panel instead: the panel's
   selection wins.
6. **Clean machine (beta smoke test, RELEASING.md step 3).** After the README's first-launch steps,
   the entry appears without logging out and works on a PDF in `~/Downloads`. Record whether a Files
   and Folders prompt appears and when. If Sparkle is in the same beta line, repeat after an in-app
   update.
7. **Before first launch (clean machine).** Before approving the app, invoke the entry if it is
   listed. Confirm the result is the README's Gatekeeper block, not a silent failure. Record it.

## 5. Implementation plan

```
M1 (spike, maintainer) ─┐
T1 (logic) ─────────────┴─► T2 (Finder entry + README) ─► T4 (beta smoke test) ─► T5 (RELEASING)
                             T3 (devops CI check, after T2)
```

Each PR ends with a clean `swift build` and a passing `swift test`, with no new warnings. PRs use
`Part of #14`, except T2, which uses `Closes #14` (it carries the user-facing change). Labels are
`project-owner`'s call. T1, T3, and T5 have no user-facing effect and probably carry
`skip-changelog`.

### M1 (maintainer, GUI): placement spike

Run manual check 1 on a local build of T2's branch, or on any build with the §2.2 keys. It takes
about 15 minutes, and the result decides whether `NSIconName` goes in T2. It also informs Open
question 1. The issue keeps `needs-decision` until Open questions 1 and 3 are answered.

### T1 (`macos-developer`): Hold and resume files handed to the app from outside

Suggested title: "Prepare the popover flow to receive PDFs from outside the app".

- `Logic.swift`: add `IncomingFiles`, `ExternalOpenAction`, and `externalOpenAction(...)` (§2.4).
- `AppModel`: add `isPresentingPanel`, `heldExternalFiles`, `openFromOutside(_:)`, and
  `resumeExternalOpen()`. Set `isPresentingPanel` around both `runModal()` calls, and call
  `resumeExternalOpen()` at the four points in §2.4.
- `Tests/UnlatchTests/ExternalOpenTests.swift` as in §4.
- Nothing calls `openFromOutside` yet.

Acceptance criteria:

- Build and tests pass, and all new tests pass.
- There is no behaviour change in the popover: browse, password, destination, and save work exactly
  as before. Check by hand once with `swift run Unlatch`.
- `git diff --stat Sources/UnlatchCore` is empty.

### T2 (`macos-developer`): Unlock PDFs from Finder's right-click menu

Suggested title: "Unlock PDFs from Finder's right-click menu".

Depends on T1, and on M1 for the `NSIconName` decision.

- Add `Sources/Unlatch/FinderHandoff.swift` (§2.3).
- `AppDelegate` wiring (§2.3).
- `Resources/Info.plist.template`: the §2.2 keys, with comments. Add `NSIconName` only if M1 says
  so. Fix the stale "UnlatchApp.swift's AppDelegate" comment if Sparkle's T2 hasn't already.
- `InfoPlistTemplateTests.swift` additions (§4).
- `README.md`, "Using the app": a short "Unlocking from Finder" paragraph. It covers the entry's
  name and where it appears (from M1), Open With > Unlatch, that Unlatch opens if it isn't running,
  and where to turn the entry off.

Acceptance criteria:

- Build and tests pass, with no new warnings under strict concurrency, and with no
  `nonisolated(unsafe)` or `@unchecked Sendable` added.
- With a `package-app.sh` bundle in `/Applications`, manual checks 2 to 5 pass. Paste the
  `pbs -dump | grep -A12 com.pablocolaiacovo.unlatch` output and a screenshot of the context menu
  into the PR.
- `Scripts/package-app.sh` is unchanged and its signature verification passes. The bundle has no
  `Contents/PlugIns`.

### T3 (`devops`): Check the Finder entry in the release workflow

Suggested title: "Verify the Finder entry in every packaged release".

Depends on T2.

- Add the "Verify Finder hand-off" step (§4 CI) to `release.yml` `build-and-package`.
- Use `::error::` annotations, matching the existing steps.

Acceptance criteria:

- A `workflow_dispatch` run on the branch is green.
- A local negative check fails the step: rename `NSMessage` in a scratch copy of the bundle's
  Info.plist.

### T4 (`release-manager` and the maintainer): Verify on a clean machine

Depends on T2 and T3, and on the first v1.2 beta. The maintainer approves the exact version, per
RELEASING.md.

- The maintainer runs manual checks 6 and 7 during the step 3 smoke test and posts the findings on
  #14: placement, TCC behaviour, and the pre-approval behaviour.
- If #8 has landed by then, repeat check 6 on the Developer ID build. Otherwise add "invoke Unlock
  with Unlatch once" to #8's clean-machine checklist (project-owner edits #8).

Acceptance criteria: the findings comment exists. If TCC or placement differs from the README, a
`macos-developer` README fix is filed before the stable tag.

### T5 (`project-owner`): Smoke-test line in RELEASING.md

Depends on T2.

- Step 3: "Right-click a PDF in Finder and choose Unlock with Unlatch, with Unlatch quit first. It
  launches and shows the file."

## 6. Open questions

1. **`needs-decision`: Is a Services entry enough for "Finder Quick Action"?** The entry shows in
   Finder's right-click menu under Services (or possibly Quick Actions, per M1), not as a guaranteed
   Quick Actions or Preview-pane item.
   **Recommendation:** yes. Ship Services and Open With in v1.2. `project-owner` files a Backlog
   follow-up, "Quick Action app extension", that depends on #8, and only if M1 shows the entry does
   not land in Quick Actions. The extension's sandbox and ad-hoc identity risks (§3.2) are not worth
   taking before #8.
2. **List Unlatch in Open With for PDFs (`Alternate` rank)?**
   **Recommendation:** yes. It's a second Finder route at no signing cost, it never changes the
   default viewer (verified), and it is what makes `open -a` and drops on the app icon work.
3. **`needs-decision`: Drop #14's dependency on #8 and rewrite its last checkbox.**
   **Recommendation:** yes. Replace "verify the extension is registered from a signed, notarized
   bundle" with "verify the Finder entry from a browser-downloaded release on a clean machine (T4),
   and again under Developer ID when #8 lands". The chosen mechanism has no Team ID or notarization
   dependency (§2.6, §2.7), so v1.2 doesn't need to wait on a paid membership. Keep #14 in v1.2.
   `project-owner` edits the issue text once this is decided.
4. **Menu item wording.**
   **Recommendation:** "Unlock with Unlatch". It names the action and the app, the way Services
   entries are expected to, and fits the README's language. "Remove PDF Password" was considered,
   but it overstates what happens to owner-restricted files, which are copied as-is.

**Resolved by the maintainer on 2026-10-09:** all four questions are accepted as recommended. A
Services entry plus Open With is enough for #14 in v1.2, and the Quick Action app extension
follow-up is filed only if M1 shows the entry does not land in Quick Actions. #14 no longer depends
on #8, and its last checkbox is rewritten as in question 3. The menu item reads "Unlock with
Unlatch".

## Sources

- [Services Properties (Apple, Services Implementation Guide)][Services Properties]: `NSServices`,
  `NSSendFileTypes`, `NSPortName`, `NSMessage`, and the `NSRequiredContext` note.
- [Quinn (Apple DTS): "macOS app extensions must have App Sandbox enabled"][Quinn, DTS]
- [NSExtensionServiceFinderPreviewIconName (Apple)](https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionattributes/nsextensionservicefinderpreviewiconname)
- [Finder Quick Actions (Daniel Jalkut, Indiestack)](https://indiestack.com/?p=709)
- [Problem receiving multiple URLs (Apple Developer Forums)][Forum 120354]
- [Launch Services release notes: LSHandlerRank values][LS release notes] and
  [Setting up a document browser app (Apple)](https://developer.apple.com/documentation/uikit/setting-up-a-document-browser-app)
- [Six Colors: Services versus Quick Actions in Finder menus][Six Colors]
- [MacScripter: moving a Quick Action out of the Quick Actions submenu (`NSIconName`)][MacScripter]
- [Many Tricks: "Quick Actions are the new Services"](https://manytricks.com/blog/?p=5876)
- Xcode 27.0 local files: the macOS Action Extension template
  (`…/Templates/Project Templates/macOS/Application Extension/Action Extension.xctemplate`) and
  `DarwinProductTypes.xcspec` (`LD_ENTRY_POINT = _NSExtensionMain` for app extensions).

[Services Properties]: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html
[Quinn, DTS]: https://developer.apple.com/forums/thread/798886
[Forum 120354]: https://developer.apple.com/forums/thread/120354
[LS release notes]: https://developer.apple.com/library/archive/releasenotes/Carbon/RN-LaunchServices/
[Six Colors]: https://sixcolors.com/?p=10921
[MacScripter]: https://macscripter.net/t/move-automator-quickaction-from-quickactions-menu-to-main-context-menu/74812
