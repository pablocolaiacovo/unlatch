# Unlock PDFs from Finder (issue #14)

Issue: #14, "Unlock PDFs from a Finder Quick Action" (`enhancement`, `area:app`, milestone v1.2).
The maintainer's comments on the issue frame it:

- Dropping PDFs on the menu bar icon is not viable (#15), so a Finder entry is the planned
  Finder-integrated way into Unlatch.
- On 2026-10-09 the issue moved from v1.1 to v1.2, pending this design. At the time its last
  checkbox asked for verification "from a signed, notarized bundle", a dependency on #8 (Developer
  ID), which is deferred in Backlog behind a paid membership.
- After this design, the maintainer accepted its open questions (2026-10-09, §6). The issue now
  reads: "Verify the Finder entry from a browser-downloaded release on a clean machine, and again
  under Developer ID when #8 lands", and its "Depends on" section says nothing is blocking, #7 is
  closed, and #8 is not a prerequisite.

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
   Confirming either panel discards them instead (§2.4).
4. No new bundle, executable, entitlement, or nested code signature. `Scripts/package-app.sh`, its
   inside-out signing from PR #52, and the release workflow's signature checks stay valid
   unchanged.
5. The issue's registration check becomes concrete and runnable under ad-hoc signing: a headless CI
   check (`/System/Library/CoreServices/pbs -read_bundle`) plus a clean-machine check in the beta
   smoke test. `pbs` is not on `PATH`, so every command in this document uses its full path.

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
| `Sources/Unlatch/AppModel.swift` | Add `openFromOutside(_:)`, `resumeExternalOpen()`, `isPresentingPanel`, `onPanelConfirmed`, and the held-files buffer. Call `resumeExternalOpen()` where work ends | `macos-developer` |
| `Sources/Unlatch/FinderHandoff.swift` | New: the Services provider, the cold-launch buffer, and burst coalescing | `macos-developer` |
| `Sources/Unlatch/AppDelegate.swift` | Own a `FinderHandoff`, set `NSApp.servicesProvider`, wire `onPanelConfirmed`, forward `application(_:open:)` | `macos-developer` |
| `Resources/Info.plist.template` | Add `NSServices` and `CFBundleDocumentTypes` | `macos-developer` |
| `Tests/UnlatchTests/ExternalOpenTests.swift` | New: pure helpers, plus `AppModel` hold-and-resume behaviour | `macos-developer` |
| `Tests/UnlatchTests/FinderHandoffTests.swift` | New: `connect(to:)` never delivers inline and restarts the coalescing timer, cold-launch bursts coalesce, `discardPending()` | `macos-developer` |
| `Tests/UnlatchTests/InfoPlistTemplateTests.swift` | Extend the existing file (Sparkle guards, `loadTemplate()`): Services and document-type guards, and the selector cross-check | `macos-developer` |
| `README.md` | "Unlocking from Finder" under "Using the app" | `macos-developer` |
| `.github/workflows/release.yml` | One step: `/System/Library/CoreServices/pbs -read_bundle` and plist assertions on the packaged app | `devops` |
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

The two version placeholders are unaffected. The Sparkle `SU*` keys already in the template sit next
to these with no interaction, and the existing Sparkle guards in
`Tests/UnlatchTests/InfoPlistTemplateTests.swift` keep passing unchanged.

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

    /// Called once by AppDelegate after StatusItemController exists. Stores
    /// deliver and, if the buffer is non-empty (on a cold launch, AppKit calls
    /// application(_:open:) before applicationDidFinishLaunching, verified in
    /// §2.8), restarts the coalescing timer with the full delay. Never
    /// delivers inline.
    func connect(to deliver: @escaping @MainActor ([URL]) -> Void)

    /// Open With, `open -a`, a drop on the app icon.
    func receive(_ urls: [URL])

    /// Drops buffered URLs and cancels the pending flush. AppModel calls it
    /// (through onPanelConfirmed) when the user confirms the "Choose PDFs…"
    /// or "Choose folder…" panel, so a hand-off received before that point
    /// can't replace the panel's selection or the batch the folder was
    /// chosen for (§2.4).
    func discardPending()

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
- **Logging.** `unlockPDFs` and `AppDelegate.application(_:open:)` each log one line on entry,
  following the app's existing `NSLog("Unlatch: …")` convention: `NSLog("Unlatch: hand-off received
  %d file(s) via %@", urls.count, "Services")` (or `"open"`). Manual check 5 relies on it to tell
  when AppKit dispatched a request relative to a modal panel (§2.4).
- **`receive(_:)`** adds the URLs to an `IncomingFiles` buffer (§2.4) and restarts a coalescing
  timer: it cancels the previous `Task`, then starts `Task { try? await Task.sleep(for: delay);
  guard !Task.isCancelled else { return }; flush() }`. `flush()` does nothing until `connect` has
  run. After that it calls `deliver(buffer.take())`. The window exists because Launch Services
  does not promise one `application(_:open:)` call per user action. An Apple forum thread documents
  9 files from one Open With arriving as 5 plus 4 [Forum 120354]. Without coalescing, the second
  call would replace the first batch (`AppModel.load` is last-wins by design). 250 ms is not
  noticeable next to an app launch or a popover animation. The Services path goes through the same
  buffer for uniformity.
- **`connect(to:)`** has one rule: it stores `deliver`, and if the buffer is non-empty it
  restarts the coalescing timer with the full delay, the same cancel-and-start that `receive` does.
  It **never calls `flush()` or `deliver` inline**, and it has no branch on the timer's state. An
  earlier timer may still be pending, or may already have fired while `deliver` was `nil` (its
  `flush()` then did nothing). In both cases the buffer is still full, the old timer (if any) is
  cancelled, and the restarted one delivers. This gives two properties:
  - **At least one full delay after the status item exists.** `connect` runs inside
    `applicationDidFinishLaunching`, right after `StatusItemController` creates the status item.
    Because the timer is restarted rather than inherited, the earliest delivery is one full
    `coalescingDelay` after `connect`. It is never in the launch turn, and never sooner because an
    earlier timer happened to be about to fire. An inline flush would call `load` → `onLoad` →
    `presentAndFocus()` before the button has been laid out in the menu bar.
  - **It still coalesces 5 plus 4.** On a cold Open With, part of a split burst (the 5) can arrive
    before `didFinishLaunching` and the rest (the 4) just after. `connect` restarts the timer for
    the 5, then the 4 go through `receive`, which restarts the same timer again. One flush delivers
    all 9 in one call. An inline flush in `connect` would deliver the 5 and let the 4 start a second
    batch, and since `load` is last-wins only the 4 would load.

  The cost is at most one extra delay (250 ms) on a cold launch with files already buffered, which
  is not noticeable next to the launch itself.
- **`discardPending()`** cancels the pending `Task` and empties the buffer. It never delivers.

`AppDelegate` changes:

```swift
private let finderHandoff = FinderHandoff()

func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let info = Bundle.main.infoDictionary
    let updater = AppUpdater(
        availability: updaterAvailability(
            bundleURL: Bundle.main.bundleURL,
            feedURL: info?["SUFeedURL"] as? String,
            publicEDKey: info?["SUPublicEDKey"] as? String),
        shortVersion: info?["CFBundleShortVersionString"] as? String)
    self.updater = updater
    statusItemController = StatusItemController(model: model, updater: updater)
    // New: after StatusItemController, which sets model.onLoad.
    NSApp.servicesProvider = finderHandoff
    model.onPanelConfirmed = { [finderHandoff] in finderHandoff.discardPending() }
    finderHandoff.connect { [model] urls in model.openFromOutside(urls) }
}

// New.
func application(_ application: NSApplication, open urls: [URL]) {
    NSLog("Unlatch: hand-off received %d file(s) via %@", urls.count, "open")
    finderHandoff.receive(urls)
}
```

The three new lines go after the existing `StatusItemController(model:updater:)` call, because
`StatusItemController.init` is what sets `model.onLoad`. The updater setup is unchanged and doesn't
interact with them. Setting `servicesProvider` in `applicationDidFinishLaunching` is enough: on a
cold launch through the Services entry, the request arrived after `didFinishLaunching` (verified).

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
`NSOpenPanel`: `browse()` and `chooseOtherFolder()` run it modally, and the design assumes AppKit
may still dispatch a Services request or an `odoc` Apple event (`application(_:open:)`) during the
modal session. That assumption is unverified (§2.8). The rules below are safe whether AppKit
dispatches such requests during the modal session or queues them until `runModal()` returns, and
manual check 5 records which one happens.

`AppModel` additions:

```swift
/// True while browse() or chooseOtherFolder() runs its modal NSOpenPanel.
private(set) var isPresentingPanel = false
/// The newest request received while busy. Each hold replaces it rather than
/// adding to it (newest wins, §3.4). private(set) so tests can read it.
@ObservationIgnored private(set) var heldExternalFiles = IncomingFiles()
/// Called when the user confirms browse()'s or chooseOtherFolder()'s panel.
/// AppDelegate wires it to FinderHandoff.discardPending() so URLs still in
/// the hand-off's coalescing buffer can't replace the panel's selection or
/// the batch the folder was chosen for.
@ObservationIgnored var onPanelConfirmed: (@MainActor () -> Void)?

/// Entry point for files from Finder. Same effect as choosing them with
/// browse(): replaces the current batch and opens the popover. Holds them
/// instead while work is in flight (externalOpenAction).
func openFromOutside(_ urls: [URL])

/// Loads held files if the model is no longer busy. Called where busy
/// periods end: after the awaits in submitPassword() and save(), and when
/// browse()'s or chooseOtherFolder()'s panel is cancelled. A confirmed
/// browse() or chooseOtherFolder() discards held files instead.
func resumeExternalOpen()
```

Rules:

- **`.loadNow`**: `load(urls)`, which already calls `onLoad` and so `presentAndFocus()`.
- **`.holdUntilIdle` because of `.working`**: replace `heldExternalFiles` with the new URLs and
  call `onLoad?()` so the popover opens on the spinner. The user sees the request was received.
- **`.holdUntilIdle` because of a panel**: replace `heldExternalFiles` with the new URLs only. The
  panel is already in front.
- **Replace, not merge.** Each `openFromOutside` call is one delivery from `FinderHandoff`, which
  has already merged a burst that Launch Services split. Two holds are therefore two separate
  requests, and the newer one wins, consistent with last-wins `load(_:)` and §3.4. Concretely the
  hold empties `heldExternalFiles` and then adds the new URLs, so `IncomingFiles` still drops
  duplicates and non-file URLs within the request.
- **`browse()`**: sets `isPresentingPanel` around `runModal()`.
  - **Cancel**: `resumeExternalOpen()` loads held files. Files still in the hand-off buffer are
    delivered by its timer as usual.
  - **Confirm**: everything received before the panel closed is discarded, wherever it is waiting:
    `heldExternalFiles` is emptied and `onPanelConfirmed?()` empties `FinderHandoff`'s buffer and
    cancels its timer. Then the panel's selection is loaded. Without the discard, a buffered
    hand-off's flush would call `openFromOutside` → `load` a moment later and replace the user's
    pick.

  What the user sees on a confirm depends on when AppKit hands over a request made while the panel
  is up, which is unverified (§2.8):
  - **Dispatched during the modal session.** `unlockPDFs` or `application(_:open:)` runs inside
    `runModal()` and the URLs go into the hand-off buffer. The coalescing `Task` is a main-actor
    job, and main-queue jobs run in the modal run-loop mode, so its timer can fire while the panel
    is up. The flush then lands in `heldExternalFiles`, because `isPresentingPanel` is true. If the
    user confirms within 250 ms, the URLs are still in the hand-off buffer instead. Either way the
    confirm discards them: the request (set A) is dropped and the panel's selection (set B) loads.
    Everything runs on the main actor and `runModal()` returns synchronously, so "waiting somewhere
    when the panel returns" means exactly "received before the user confirmed".
  - **Queued until `runModal()` returns.** The request is handled only after the confirm has
    discarded and loaded set B. It reaches the hand-off buffer as a request newer than the pick,
    and its flush replaces set B with set A about 250 ms later. That is the normal newest-wins rule
    (§3.4) and is acceptable: from the app's point of view the request did arrive after the pick.

  A hand-off received after the panel closes is newer than the pick and replaces it, by the same
  rule.
- **`chooseOtherFolder()`**: sets `isPresentingPanel` around `runModal()`, and handles the panel
  closing the same way as `browse()` (maintainer decision, 2026-10-21, open question 5). A confirm
  is `runModal()` returning `.OK` with a non-nil `panel.url`. Anything else is a cancel.
  - **Cancel**: `resumeExternalOpen()` loads held files. Files still in the hand-off buffer are
    delivered by its timer as usual.
  - **Confirm**: `heldExternalFiles` is emptied and `onPanelConfirmed?()` empties `FinderHandoff`'s
    buffer and cancels its timer. Then the chosen folder is applied (`chosenFolder`, `destination =
    .other`). Without the discard, held or buffered files would load and replace the batch the user
    just chose a folder for.

  The two dispatch cases above apply unchanged, with the folder pick in place of set B: a request
  dispatched during the modal session is discarded by the confirm, and a request queued until
  `runModal()` returns is newer than the pick and replaces the batch about 250 ms later
  (newest wins, §3.4).
- **End of `submitPassword()`'s and `save()`'s tasks**: `resumeExternalOpen()`, so the newest
  request wins. Only the newest request held during the work is kept (replace, above). After a save this replaces the done step. The files were written, but the
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
(`pluginkit`, `/System/Library/CoreServices/pbs -dump`, and `lsregister -dump` show no
leftovers). The repository was not touched,
apart from a baseline `swift build` and `swift test` on `main`, both clean.

**Verified:**

1. An ad-hoc signed (`flags=0x2(adhoc)`, `TeamIdentifier=not set`), non-sandboxed `LSUIElement`
   app with the `NSServices` entry from §2.2 shows up in `/System/Library/CoreServices/pbs -dump`
   after `lsregister -f` and `/System/Library/CoreServices/pbs -update`. It needed no entitlements.
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
7. `/System/Library/CoreServices/pbs -read_bundle <app>` prints the parsed service entries
   **without registering** them. It is usable as a CI check.
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
- **Whether AppKit dispatches a Services request or an `odoc` Apple event while
  `NSOpenPanel.runModal()` is running**, or queues it until the modal session ends. Nobody has
  checked this. §2.4's discard on confirm is safe either way, but the visible result of manual
  check 5b differs: set B stays if requests are dispatched during the modal session, and set A
  replaces it about 250 ms after the confirm if they are queued. Check 5 records which happens.
  (That main-actor `Task` jobs run while the panel is up is not in question: they go through the
  main queue, which the modal run-loop mode services.)
- Whether Finder's multi-file Open With arrives in one `application(_:open:)` call. Coalescing
  makes the answer irrelevant, including on a cold launch (§2.3, manual check 2b).
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
- **Hand-off while "Choose PDFs…" or "Choose folder…" is up**: held. Cancelling the panel loads it.
  Confirming either panel discards it, along with anything still in the hand-off buffer, and then
  applies the panel's result (§2.4).
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

The same rule applies to held files: a request held while busy replaces any request held before it
(§2.4), and the newest held request loads when the work ends. The exception is a confirmed
"Choose PDFs…" or "Choose folder…" panel, which discards the held request instead (§2.4). The only
merge is inside `FinderHandoff`, which coalesces a burst that Launch Services split from one user
action, because that is one request, not two.

### 3.5 No Xcode project

When #14 was filed it listed #7 (packaging the app bundle) as a dependency, on the expectation that
an extension would force an Xcode project. #7 is now closed, and #14's "Depends on" section says
nothing is blocking. Neither the chosen design nor the deferred extension needs an Xcode project
(§2.8). SwiftPM stays the only build system.

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
    spinner), leaves `files` unchanged, and holds `u` (`heldExternalFiles.urls == [u]`).
  - **A newer hold replaces the older one.** With `step = .working`, `openFromOutside([a])` then
    `openFromOutside([b])` leaves `heldExternalFiles.urls == [b]`, not `[a, b]` (§2.4, §3.4). Then
    setting `step = .password` and calling `resumeExternalOpen()` fires `onLoad` and empties
    `heldExternalFiles`.
  - Setting `step = .password` and then calling `resumeExternalOpen()` loads, so `onLoad` fires
    again. A second `resumeExternalOpen()` does nothing.
  - `openFromOutside([])` does nothing.
  - `runModal()` can't be driven from a unit test, so T1 factors what `chooseOtherFolder()` does
    after its panel closes into an internal method the tests call directly, for example
    `folderPanelClosed(url:)`, where `nil` means cancelled. The name is T1's call. With
    `isPresentingPanel = true`, `openFromOutside([a])` holds `a`, then `isPresentingPanel = false`:
    - **Cancelled folder pick resumes.** Closing `chooseOtherFolder()`'s panel with `nil` fires
      `onLoad` and empties `heldExternalFiles`.
    - **Confirmed folder pick discards.** Closing it with a folder URL empties `heldExternalFiles`,
      calls `onPanelConfirmed` once, does not call `onLoad`, and sets `chosenFolder` to that URL and
      `destination` to `.other`.

`InfoPlistTemplateTests.swift`: extend the existing file, which already holds the Sparkle guards,
and reuse its private `loadTemplate()` helper (it reads the template via `#filePath`, substitutes
the two placeholders, and parses with `PropertyListSerialization`). Update its header comment to
mention this design next to `Design/sparkle-updates.md`. Add:

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

`FinderHandoffTests.swift`. Every case is a `@MainActor @Test`. Each builds a `FinderHandoff`
with a short real delay and a recording `deliver` closure (or a small `@MainActor` recorder class)
that appends each call's `[URL]` to an array. There is no injectable clock: the tests use the real
`Task.sleep` delay. **Positive checks** poll in 20 ms `Task.sleep` steps for up to 2 s until the
expected call appears. **Negative checks** sleep for a fixed window and then expect no new call.

- **`connect` never delivers inline** (delay 50 ms). `receive([a, b])`, `connect(to: record)`, then
  `#expect(calls.isEmpty)` on the very next line. This is deterministic: nothing can run between
  the two statements on the main actor. Then poll: exactly one call, `[a, b]`.
- **`connect` delivers files buffered before it when no timer is pending** (delay 50 ms).
  `receive([a])`, then a fixed 200 ms wait so the first timer fires while `deliver` is `nil` and
  does nothing. `connect(to: record)`, `#expect(calls.isEmpty)`, then poll: one call with `[a]`.
  Without the restart in `connect`, nothing would ever deliver `[a]`, so this case fails if the rule
  is missing.
- **`connect` restarts the timer with the full delay** (delay 400 ms). `receive([a])`, wait 300 ms,
  `connect(to: record)`, then a fixed 200 ms negative window: no call. An inherited timer would
  have fired about 100 ms after `connect`, and the restarted one fires about 400 ms after it, so the
  window sits between the two with about 100 ms of margin on the inherited side and 200 ms on the
  restarted side. Then poll: exactly one call with `[a]`.
- **Cold-launch burst coalesces** (delay 50 ms). `receive` 5 URLs, `connect(to: record)`, `receive`
  4 more, then poll until `calls` is non-empty. Expect exactly one call with all 9 URLs in order.
  Then a fixed 200 ms negative window: still one call.
- **`discardPending()`** (delay 50 ms). After `connect`, `receive([a])`, `discardPending()`, then a
  fixed 200 ms negative window: no call. A later `receive([b])` is polled for and delivers `[b]`
  alone.

The 2 s polling bound is generous next to the delays, so positive checks don't depend on scheduler
timing. The negative windows are at least four times the 50 ms delay, except in the restart case,
where the margins are stated above. `Tests/UnlatchCoreTests`, the fixtures, and `Scripts/generate-fixtures.sh` don't change.

### CI (`devops`, `release.yml` `build-and-package`)

A "Verify Finder hand-off" step after "Verify signature":

- `/System/Library/CoreServices/pbs -read_bundle dist/Unlatch.app` output contains
  `NSMessage = unlockPDFs`, `NSPortName = Unlatch`, and `com.adobe.pdf`. `pbs` is not on the
  runner's `PATH`, so call it by full path. Capture the output into a variable and then grep (no
  `pbs | grep -q` under pipefail, as PR #52 learned).
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
2. **Cold launch.**
   - a. **Services.** Quit Unlatch. Select three PDFs (one password-protected, one owner-restricted,
     one damaged) and choose the entry. Unlatch launches, the popover opens under the icon with
     three rows, and it goes to the password step.
   - b. **Cold Open With and `open -a`, multiple files.** Quit Unlatch. Select nine PDFs in Finder
     and choose Open With > Unlatch. Unlatch launches, the popover opens anchored under the menu bar
     icon (not at a screen corner or detached), and it lists **all nine** files, not a subset.
     Quit again and repeat from Terminal with
     `open -a /Applications/Unlatch.app ~/pdfs/{1..9}.pdf`. Same result.
3. **Warm and mid-flow.** Repeat with the popover closed, then open on the destination step. The new
   batch replaces the old. Start a save of a large PDF and invoke the entry during the spinner: the
   new batch loads when the save finishes.
4. **Selection rules.** With a PDF plus a `.txt` selected, the entry and Open With > Unlatch don't
   appear. Open With > Unlatch on two PDFs gives one batch of two. Preview stays the default for
   double-click.
5. **Panel open.** Use two disjoint sets of PDFs: set A for `perform`, set B for the panel. In a
   second Terminal window, run `log stream --process Unlatch --predicate 'eventMessage BEGINSWITH
   "Unlatch: hand-off"'` to watch the hand-off log line (§2.3). This check also answers the §2.8
   question of whether AppKit dispatches requests during a modal panel.
   - a. Click "Choose PDFs…". While the panel is up, run `./perform "Unlock with Unlatch" A1.pdf
     A2.pdf` from Terminal and wait two seconds. **Record** whether the hand-off line (`via
     Services`, from `unlockPDFs`; `via open` if it came through `application(_:open:)`) is logged
     while the panel is still up, and whether `perform` prints before the panel closes. Then
     **cancel** the panel. Set A loads in either case: held and resumed if the request was
     dispatched during the panel, or delivered by the hand-off timer if it was queued.
   - b. Click "Choose PDFs…", run the same `perform`, wait two seconds, and **record** the same two
     things. Then select set B and **confirm**. Expected result, by what was recorded:
     - **Logged while the panel was up** (dispatched during the modal session): set B loads. Wait
       another two seconds: the popover still shows set B, and set A never appears.
     - **Logged only after the confirm** (queued until `runModal()` returns): set B loads, then set
       A replaces it about 250 ms later. That is newest-wins (§3.4) and passes.
     Post the recorded outcome on #14 with the T2 PR.
   - c. With set B loaded on the password step, run `perform` with set A again. Set A replaces it
     (newest wins, §3.4).
6. **Clean machine (beta smoke test, RELEASING.md step 3).** After the README's first-launch steps,
   the entry appears without logging out and works on a PDF in `~/Downloads`. Record whether a Files
   and Folders prompt appears and when. If Sparkle is in the same beta line, repeat after an in-app
   update.
7. **Before first launch (clean machine).** Before approving the app, invoke the entry if it is
   listed. Confirm the result is the README's Gatekeeper block, not a silent failure. Record it.

## 5. Implementation plan

```
M1 (spike, maintainer) ─┐
T1 (logic) ─────────────┴─► T2 (Finder entry + README) ─┬─► T3 (devops CI check) ─► T4 (beta smoke test)
                                                         └─► T5 (RELEASING line)
```

T3 and T5 each depend only on T2 and can land in either order. T4 depends on T2 and T3. T5 should
land before the first v1.2 beta so the smoke-test line is in RELEASING.md when T4 runs, but it isn't
a hard dependency: T4 runs manual checks 6 and 7 from this document either way.

Each PR ends with a clean `swift build` and a passing `swift test`, with no new warnings. PRs use
`Part of #14`, except T2, which uses `Closes #14` (it carries the user-facing change). Labels are
`project-owner`'s call. T1, T3, and T5 have no user-facing effect and probably carry
`skip-changelog`.

### M1 (maintainer, GUI): placement spike

Run manual check 1 on a local build of T2's branch, or on any build with the §2.2 keys. It takes
about 15 minutes, and the result decides whether `NSIconName` goes in T2. Open questions 1 and 3,
the two that needed a decision, were resolved by the maintainer on 2026-10-09 (§6), so the issue no
longer needs `needs-decision`. Under that decision, M1's result also decides whether `project-owner`
files the Quick Action app extension follow-up (only if the entry does not land in Quick Actions).

### T1 (`macos-developer`): Hold and resume files handed to the app from outside

Suggested title: "Prepare the popover flow to receive PDFs from outside the app".

- `Logic.swift`: add `IncomingFiles`, `ExternalOpenAction`, and `externalOpenAction(...)` (§2.4).
- `AppModel`: add `isPresentingPanel`, `heldExternalFiles`, `onPanelConfirmed`,
  `openFromOutside(_:)`, and `resumeExternalOpen()`. Set `isPresentingPanel` around both
  `runModal()` calls, and call `resumeExternalOpen()` at the four points in §2.4 (the ends of
  `submitPassword()`'s and `save()`'s tasks, and a cancelled `browse()` or `chooseOtherFolder()`
  panel). Both panels discard on a confirm: empty `heldExternalFiles` and call
  `onPanelConfirmed?()`, then `load(panel.urls)` for `browse()` or apply the chosen folder for
  `chooseOtherFolder()`.
  Each hold replaces `heldExternalFiles` rather than adding to it.
- Handle open question 7 (a superseded batch's Save stays live while the new batch loads) once it
  is decided. T1 is not done until a load from a step that shows Save can't let the old batch's
  save write into the new one.
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

- Add `Sources/Unlatch/FinderHandoff.swift` (§2.3), including `discardPending()`, the `connect(to:)`
  rule (store `deliver`, restart the timer if the buffer is non-empty, never deliver inline), and
  the hand-off log line in `unlockPDFs`.
- `AppDelegate` wiring (§2.3): the three new lines after the existing
  `StatusItemController(model: model, updater: updater)` call, plus `application(_:open:)` with its
  log line.
- `Resources/Info.plist.template`: the §2.2 keys, with comments. Add `NSIconName` only if M1 says
  so.
- Extend `Tests/UnlatchTests/InfoPlistTemplateTests.swift` with the §4 Services, document-type,
  and selector cross-check tests, reusing its `loadTemplate()`. The existing Sparkle tests stay as
  they are.
- Add `Tests/UnlatchTests/FinderHandoffTests.swift` (§4).
- `README.md`, "Using the app": a short "Unlocking from Finder" paragraph. It covers the entry's
  name and where it appears (from M1), Open With > Unlatch, that Unlatch opens if it isn't running,
  and where to turn the entry off.

Acceptance criteria:

- Build and tests pass, with no new warnings under strict concurrency, and with no
  `nonisolated(unsafe)` or `@unchecked Sendable` added.
- The `FinderHandoffTests` pass, in particular: after `receive` of 5 URLs, `connect`, and
  `receive` of 4 more, `deliver` is not called inline and is then called exactly once with all 9.
- With a `package-app.sh` bundle in `/Applications`, manual checks 2 (both 2a and 2b) to 5 pass,
  and check 5's recorded dispatch behaviour is in the PR.
  Paste the
  `/System/Library/CoreServices/pbs -dump | grep -A12 com.pablocolaiacovo.unlatch` output and a
  screenshot of the context menu into the PR.
- `Scripts/package-app.sh` is unchanged and its signature verification passes. The bundle has no
  `Contents/PlugIns`.

### T3 (`devops`): Check the Finder entry in the release workflow

Suggested title: "Verify the Finder entry in every packaged release".

Depends on T2.

- Add the "Verify Finder hand-off" step (§4 CI) to `release.yml` `build-and-package`. Invoke
  `pbs` as `/System/Library/CoreServices/pbs -read_bundle dist/Unlatch.app`; it is not on the
  runner's `PATH`.
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

Depends on T2 only. Land it before the first v1.2 beta if possible (see the plan diagram).

- Step 3: "Right-click a PDF in Finder and choose Unlock with Unlatch, with Unlatch quit first. It
  launches and shows the file."

## 6. Open questions

1. **Resolved 2026-10-09 (was `needs-decision`): Is a Services entry enough for "Finder Quick
   Action"?** The entry shows in
   Finder's right-click menu under Services (or possibly Quick Actions, per M1), not as a guaranteed
   Quick Actions or Preview-pane item.
   **Recommendation:** yes. Ship Services and Open With in v1.2. `project-owner` files a Backlog
   follow-up, "Quick Action app extension", that depends on #8, and only if M1 shows the entry does
   not land in Quick Actions. The extension's sandbox and ad-hoc identity risks (§3.2) are not worth
   taking before #8.
2. **List Unlatch in Open With for PDFs (`Alternate` rank)?**
   **Recommendation:** yes. It's a second Finder route at no signing cost, it never changes the
   default viewer (verified), and it is what makes `open -a` and drops on the app icon work.
3. **Resolved 2026-10-09 (was `needs-decision`): Drop #14's dependency on #8 and rewrite its last
   checkbox.**
   **Recommendation:** yes. Replace "verify the extension is registered from a signed, notarized
   bundle" with "verify the Finder entry from a browser-downloaded release on a clean machine (T4),
   and again under Developer ID when #8 lands". The chosen mechanism has no Team ID or notarization
   dependency (§2.6, §2.7), so v1.2 doesn't need to wait on a paid membership. Keep #14 in v1.2.
   `project-owner` has since edited the issue text accordingly; it now reads as quoted at the top
   of this document.
4. **Menu item wording.**
   **Recommendation:** "Unlock with Unlatch". It names the action and the app, the way Services
   entries are expected to, and fits the README's language. "Remove PDF Password" was considered,
   but it overstates what happens to owner-restricted files, which are copied as-is.

**Resolved by the maintainer on 2026-10-09:** all four questions are accepted as recommended. A
Services entry plus Open With is enough for #14 in v1.2, and the Quick Action app extension
follow-up is filed only if M1 shows the entry does not land in Quick Actions. #14 no longer depends
on #8, and its last checkbox is rewritten as in question 3. The menu item reads "Unlock with
Unlatch".

### Raised in review

These came up in the 2026-10-21 re-review of PR #56. Question 5 was resolved by the maintainer on
2026-10-21. Questions 6 and 7 have no decision yet, and this document does not make one.

5. **Resolved by the maintainer on 2026-10-21: Confirming `chooseOtherFolder()` resumes held
   files.** As designed (§2.4),
   `chooseOtherFolder()` calls `resumeExternalOpen()` after its panel closes whether the user
   confirms or cancels. On a confirm, held files then load and replace the batch the user just
   chose a folder for. That does not match `browse()`, where a confirm discards anything received
   during the panel. Is that intended, or should a confirmed folder pick discard held files (or
   keep holding them) the way a confirmed `browse()` does?
   **Maintainer's decision (2026-10-21):** "a confirmed chooseOtherFolder() discards held files,
   the same as a confirmed browse()." §2.4, §2.9, §4, and T1 follow it.
6. **Manual check 5 coverage.** Check 5 drives only the Services entry (`perform`) during the
   "Choose PDFs…" panel. It does not cover Open With (`application(_:open:)`) arriving during a
   panel, and it does not cover the "Choose folder…" panel from `chooseOtherFolder()`. Should check
   5 grow cases for those, or is the Services case enough to stand for them?
7. **A superseded batch's Save stays live while the new batch loads.** This is a gap the design
   introduces, not one on `main`: today `load(_:)` only starts from the idle step, which has no
   Save button. With this design, `openFromOutside` (`.loadNow`) and `resumeExternalOpen()` can
   call `load(_:)` from `.destination`, and from other steps that show Save. `load` changes `step`
   only after classification finishes, so until then the old batch's Save is still enabled. A
   click in that window starts `save()` for the old batch, and its completion can write into the
   new batch, which is exactly what Goal 3 rules out. T1 must handle it. Possible fixes include
   disabling Save while a load is in flight, or having `save()` ignore its result when the batch
   it started with has been superseded (for example by checking `loadGeneration`). Which one is
   open.

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
