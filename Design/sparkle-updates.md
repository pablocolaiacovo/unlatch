# In-app updates with Sparkle (issue #13)

Issue: #13, "Add in-app auto-updates with Sparkle" (`enhancement`, `area:app`, `area:release`,
milestone v1.1). The maintainer's comment on the issue overrides the body in four places:

- Releases stay ad-hoc signed and not notarized (#8 is deferred).
- "Verify the whole bundle notarizes" becomes: `codesign --verify --deep --strict` passes, and the
  app loads Sparkle at launch.
- Hardened runtime stays off in ad-hoc mode.
- The real upgrade test records whether Gatekeeper or privacy (TCC) prompts come back.

Issue #57 ("Move the version, update check, and Open at Login into an ellipsis menu in the popover
footer", maintainer decision of 2026-10-09, option C) replaces the footer layout this design
originally gave T3. §2.4, §2.5, §3.8, §4, and T3 in §5 follow #57. The exploration branch
`explore/footer-options` (commit 5b650f3) is reference only and does not ship.

**Maintainer decisions of 2026-10-15**, made after the `v1.1.0-beta.2` → `v1.1.0-beta.3` upgrade
test passed, change how a scheduled update reaches the user. They replace the earlier behaviour,
where Sparkle showed its own window for a scheduled update and the footer indicator only survived
when that window went behind:

1. **Background checks run once a day, explicitly.** `Resources/Info.plist.template` sets
   `SUScheduledCheckInterval` to `86400`. It was unset, relying on Sparkle's one-day default.
   `SUEnableAutomaticChecks` stays unset, so Sparkle's second-launch prompt still asks for consent
   (option A). `SUAllowsAutomaticUpdates` stays `false`.
2. **Sparkle never shows a window for a scheduled update on its own**, not even in immediate focus
   right after launch. Only the in-app indicator appears: the footer's accent "Update Available"
   button, the dot on the ellipsis, and the "Update Available…" menu item. Clicking either calls
   `checkForUpdates()`, and Sparkle shows the update it already found.
3. **The menu bar status item also shows a dot** while an update is available, so it is noticed
   without opening the popover. It clears together with the popover's indicator.

§2.4.1, §2.4.3, §2.5, §2.11, §3.9, §3.10, §4, T8 to T10 in §5, and §6 carry
these decisions. They change `Sources/Unlatch/AppUpdater.swift` and the update configuration in
`Resources/Info.plist.template`, both on RELEASING.md's upgrade-test trigger list, so
`v1.1.0-beta.4` must re-run the upgrade test from `v1.1.0-beta.3` (§4, T10).

## 1. Summary

Users who install from the zip can't currently find out that a newer version exists. This change
embeds Sparkle 2. The app checks an EdDSA-signed appcast hosted on GitHub Pages and offers new
versions with their release notes. When the user accepts, it installs the update in place and
relaunches. The popover footer becomes an ellipsis ("…") menu next to Quit (#57): the menu holds
the version, "Check for Updates…", and Open at Login. A scheduled check never opens a window by
itself: when it finds an update, an accent "Update Available" button and a dot on the ellipsis
appear in the footer, and a dot appears on the menu bar icon, until the user looks at the update
(2026-10-15). Scheduled checks run once a day. The release
workflow signs every published `Unlatch.zip` with an ed25519 key held as a GitHub Actions secret,
then updates and deploys the appcast. Beta tags go to a `beta` channel, which only beta builds
follow.

### Goals

1. Sparkle 2.10.0 is a SwiftPM dependency of the `Unlatch` target only. `UnlatchCore` gets no new
   imports and no API changes.
2. `Scripts/package-app.sh` embeds `Sparkle.framework` in `Contents/Frameworks` and signs it
   inside-out with the same `SIGN_IDENTITY` as the app. Hardened runtime stays off while the
   identity is ad-hoc. The signing code is laid out so that #8 only has to add flags in one place.
3. The popover footer's ellipsis menu gets "Check for Updates…", which is disabled while Sparkle
   can't start a check. When a scheduled check finds an update the user hasn't looked at yet, the
   footer shows an "Update Available" button, the ellipsis gets a dot, and the menu item reads
   "Update Available…" (§6 question 5). The status item icon gets a dot too (§2.4.3). Sparkle
   shows no window for a scheduled update until the user clicks one of these (2026-10-15).
4. The release workflow generates and signs `appcast.xml` and deploys it to GitHub Pages. Stable
   tags go to the default channel and `-beta.N` tags go to the `beta` channel.
5. Verification has three parts: unit tests for the pure decisions, CI checks on signatures,
   layout, and launch, and a real N → N+1 upgrade test on a clean Mac. That test also records what
   happens with Gatekeeper, TCC, and App Management.

### Non-goals

- Delta updates. The release workflow passes `--maximum-deltas 0` explicitly.
- Silent automatic updates. The Info.plist sets `SUAllowsAutomaticUpdates` to `false`, which
  removes Sparkle's "Automatically download and install" option. Sparkle's own second-launch
  prompt asks for consent before any scheduled check runs.
- A UI to opt in to betas. A build follows the beta channel if and only if it is itself a beta
  (§2.5).
- Signed feeds (`SURequireSignedFeed` plus `SUVerifyUpdateBeforeExtraction`). This is deferred, see
  §3.6.
- Developer ID signing, hardened runtime, and notarization. Those are #8. This design only prepares
  the seam for them (§2.3).
- Sandboxing. The app isn't sandboxed: the repository has no entitlements file and `package-app.sh`
  passes no `--entitlements`. Sparkle's XPC services are removed (§2.3).
  `SUEnableInstallerLauncherService` is not set.
- Dock or notification reminders, or a settings window. Besides Sparkle's own windows, the update
  UI is the popover footer (its ellipsis menu item, the "Update Available" button, and the dot) and
  the dot on the status item icon (§2.4.3). The status item dot was a non-goal until the
  maintainer added it on 2026-10-15.
- A user setting for the check interval. Scheduled checks run once a day
  (`SUScheduledCheckInterval` = 86400, 2026-10-15).
- Escalating a long-ignored update. An update the user never clicks stays behind the indicator
  until they act or quit the app (§2.4.1, "Lifecycle of a found update").
- Other menu items such as About, Settings, or Copy Version, and moving Quit into the menu. #57
  rules these out.
- Updating v1.0.0 installs. v1.0.0 doesn't contain Sparkle, so those users install v1.1.0 by hand
  once. The README says so.

## 2. Design

### 2.1 Module and file map

| File | Change | Owner |
| --- | --- | --- |
| `Package.swift` | Add the Sparkle package dependency, the `Sparkle` product on the `Unlatch` target, and the `@executable_path/../Frameworks` rpath linker flag | `macos-developer` |
| `Package.resolved` | New file, committed (the existing `.gitignore` comment already expects it) | `macos-developer` |
| `Resources/Info.plist.template` | Add `SUFeedURL`, `SUPublicEDKey`, and `SUAllowsAutomaticUpdates`. T8: add `SUScheduledCheckInterval` = `86400` | `macos-developer` |
| `Sources/Unlatch/Logic.swift` | T2 (merged in #54): `UpdaterAvailability`, `updaterAvailability(...)`, `allowedUpdateChannels(forVersion:)`, `UpdateButtonState`, and `updateButtonState(...)`. T3: `UpdateFooterPresentation` and `updateFooterPresentation(for:)`. T8: `UpdateReminderEvent`, `sparkleShowsScheduledUpdate(inImmediateFocus:)`, and `updateIndicatorShown(after:current:)`. T9: `StatusItemPresentation` and `statusItemPresentation(hasLockedWork:updateState:)` (§2.5) | `macos-developer` |
| `Sources/Unlatch/AppUpdater.swift` | New: wraps `SPUStandardUpdaterController`, `@MainActor @Observable`. T8: Sparkle never shows a scheduled update itself (§2.4.1) | `macos-developer` |
| `Sources/Unlatch/AppDelegate.swift` | Create and own an `AppUpdater`, then pass it to `StatusItemController` | `macos-developer` |
| `Sources/Unlatch/StatusItemController.swift` | Pass the updater into the hosting controller. Close the popover before Sparkle presents a window. T9: render the status item from `statusItemPresentation(...)`, with the dot and the accessibility value (§2.4.3) | `macos-developer` |
| `Sources/Unlatch/PopoverHostingController.swift` | `init(model:updater:)` | `macos-developer` |
| `Sources/Unlatch/Views/PopoverView.swift` | Replace the footer: ellipsis menu (version, Check for Updates…, Open at Login), the conditional "Update Available" button, the dot, and the unchanged Quit button (§2.4, #57) | `macos-developer` |
| `Tests/UnlatchTests/UpdaterLogicTests.swift` | T2 (merged in #54): tests for the three pure helpers. T3: tests for `updateFooterPresentation(for:)`. T8: tests for the reminder reducer and the no-window decision | `macos-developer` |
| `Tests/UnlatchTests/StatusItemLogicTests.swift` | T9: tests for `statusItemPresentation(...)` | `macos-developer` |
| `Tests/UnlatchTests/InfoPlistTemplateTests.swift` | New: guards on the template's Sparkle keys. T8: `SUScheduledCheckInterval` is `86400` | `macos-developer` |
| `README.md` | T3: the Open at Login paragraph describes the menu. T6: Updates section (including the once-a-day check, the indicator, and the menu bar dot), the privacy paragraph, and the findings from the upgrade test | `macos-developer` |
| `docs/screenshot.png` | T3: retake it with the new footer. It already predates #51 | `macos-developer` |
| `Sources/Unlatch/AppModel.swift`, `Tests/UnlatchTests/LoginItemTests.swift` | T3: remove `loginItemRevision`, its bump in `refreshLoginItem()`, and the tests that only cover it (§2.4.2) | `macos-developer` |
| `Scripts/package-app.sh` | Embed, trim, and sign Sparkle inside-out. Add `--sequesterRsrc` to the zip | `devops` |
| `Scripts/update-appcast.sh` | New: strip, generate, and validate the appcast. Runnable locally with a throwaway key | `devops` |
| `Scripts/appcast-drop-build.xsl` | New: removes items whose build number equals the new one (§2.6) | `devops` |
| `.github/workflows/release.yml` | Extra verification in `build-and-package`, plus new `appcast` and `deploy-feed` jobs | `devops` |
| `RELEASING.md` | Feed checks in the release checklist, key custody, and the #8 notes for Sparkle | `project-owner` |

`Sources/UnlatchCore` and `Tests/UnlatchCoreTests` are not touched. No update state goes into
`AppModel`; it lives in its own object (§2.4). T3's only `AppModel` change is removing
`loginItemRevision`, which no view reads once the checkbox becomes a menu item (§2.4.2), together
with its three observer tests in `Tests/UnlatchTests/LoginItemTests.swift`. `LoginItem.swift` and
the login item logic in `Logic.swift` are not touched: Open at Login moves into the menu, but what
it does underneath stays as #51 built it.

### 2.2 Dependency, version pin, and rpath

```swift
// Package.swift (excerpt)
dependencies: [
    // Exact pin: package-app.sh relies on this release's bundle layout
    // (Versions/B, Autoupdate, Updater.app, XPCServices). Bump deliberately,
    // in its own PR, and re-run the release workflow's dry run.
    // 2.9.2 or later is mandatory: CVE-2026-47122 affects <= 2.9.1.
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
],
targets: [
    .executableTarget(
        name: "Unlatch",
        dependencies: ["UnlatchCore", .product(name: "Sparkle", package: "Sparkle")],
        linkerSettings: [
            // Inside Unlatch.app the framework lives in Contents/Frameworks.
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            // No `@loader_path` flag: SwiftPM already adds it to every
            // executable, so `swift run Unlatch` and the test runner find the
            // framework next to the binary in .build/<config>/ (verified, see
            // §2.10). Adding it again only produces
            // `ld: warning: duplicate -rpath '@loader_path' ignored`.
        ]
    ),
]
```

Why these choices:

- **Version.** 2.10.0 (2026-09-13) is the latest release. Its minimum OS is macOS 12, which is
  below our macOS 14 floor. 2.9.2 or later is required because of CVE-2026-47122, an XPC listener
  in the installer that accepted unverified connections. The pin is `exact:`, not `from:`, because
  `package-app.sh` trims and re-signs the framework based on its internal layout. A minor Sparkle
  release could change that layout. Each bump should be its own PR that has to pass the release
  dry run.
- **Binary target.** Sparkle's `Package.swift` declares a checksummed `binaryTarget`, which is
  `Sparkle-for-Swift-Package-Manager.zip` containing `Sparkle.xcframework` plus `bin/`. A universal
  `swift build -c release --arch arm64 --arch x86_64` places a universal `Sparkle.framework` at
  `.build/release/Sparkle.framework`, next to the `Unlatch` binary. `swift package resolve` puts
  the tools (`generate_appcast`, `sign_update`, `generate_keys`) in
  `.build/artifacts/sparkle/Sparkle/bin/`. Because CI gets its tools this way, they always match
  the embedded framework.
- **Rpath.** Only one flag is needed: `@executable_path/../Frameworks`, which is what the bundle
  relies on and what `package-app.sh` checks for. SwiftPM on the pinned toolchain (Xcode 27.0,
  27A266a, Swift 6.4) already adds `@loader_path` to every executable's `LC_RPATH`, in debug and
  universal release builds, and even on `main` without Sparkle. That keeps `swift run Unlatch`
  working, which the README documents. An explicit `-rpath @loader_path` is therefore omitted (PR
  #54 does the same): it only triggers `ld: warning: duplicate -rpath '@loader_path' ignored`.
  Re-add it only if a future toolchain stops adding it. `Package.swift` is the place for the flag,
  because patching the binary with `install_name_tool` in the script would only cover the bundle.
- **`unsafeFlags` and library consumers.** SwiftPM only rejects `unsafeFlags` in a dependency when
  the target is in the build graph of the product being consumed. The flags sit on the `Unlatch`
  executable target, which is not part of the `UnlatchCore` library product, so remote consumers
  of `UnlatchCore` still build. I verified this with a `file://` git dependency (§2.10).
  The cost is that consumers now also clone Sparkle and download its roughly 26 MB artifact during
  resolution, even though nothing of it is linked. See §3.4.

`ci.yml` needs no change. Its cache key already hashes `**/Package.resolved`, and `swift test`
passes with a test target that depends on an executable linking Sparkle (verified).

### 2.3 Bundling and inside-out signing (`Scripts/package-app.sh`)

The binary decides whether Sparkle gets embedded. If `otool -L` on the built binary shows
`@rpath/Sparkle.framework/`, the script embeds the framework. If the binary links Sparkle but the
framework is missing, the script fails. If the binary doesn't link Sparkle, the script skips this
step. That way the devops task can merge before the dependency lands without breaking `main`'s
packaging, the same way the script already handles a missing iconset. There is no flag or
environment variable to keep in sync.

Sequence after "Writing Info.plist" and the icon step, replacing today's single `codesign` call:

```bash
# One argument list for every signature in the bundle, nested code included.
# Issue #8: append `--options runtime --timestamp` HERE, and only here, when
# SIGN_IDENTITY becomes a Developer ID identity. Never while ad-hoc: under an
# ad-hoc signature, hardened runtime turns on library validation, and dyld
# then refuses to load the embedded Sparkle.framework.
CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
sign() { codesign "${CODESIGN_ARGS[@]}" "$@"; }

BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
# Capture otool output and grep the variable: `otool | grep -q` under
# pipefail fails intermittently (grep exits early, otool dies of SIGPIPE).
LINKED_LIBS="$(otool -L "$BINARY")"
if grep -q '@rpath/Sparkle.framework/' <<<"$LINKED_LIBS"; then
    echo "==> Embedding Sparkle.framework"
    SPARKLE_SRC="$REPO_ROOT/.build/release/Sparkle.framework"
    [[ -d "$SPARKLE_SRC" ]] || { echo "error: binary links Sparkle but $SPARKLE_SRC is missing" >&2; exit 1; }
    LOAD_COMMANDS="$(otool -l "$BINARY")"
    grep -q '@executable_path/../Frameworks' <<<"$LOAD_COMMANDS" \
        || { echo "error: binary has no @executable_path/../Frameworks rpath (Package.swift linkerSettings)" >&2; exit 1; }

    FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    ditto "$SPARKLE_SRC" "$FW"                       # ditto, not cp: keeps the Versions/ symlinks
    [[ -d "$FW/Versions/B" ]] || { echo "error: Sparkle layout changed (no Versions/B); revisit #13's design" >&2; exit 1; }
    lipo "$FW/Versions/B/Sparkle" -verify_arch arm64 x86_64

    # Not sandboxed: Sparkle's XPC services are unused. Sparkle's sandboxing
    # guide allows removing them. Remove the versioned directory AND the
    # top-level symlink; a dangling symlink fails --strict verification.
    rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"

    echo "==> Signing Sparkle inside-out (SIGN_IDENTITY=$SIGN_IDENTITY)"
    sign "$FW/Versions/B/Autoupdate"
    sign "$FW/Versions/B/Updater.app"
    sign "$FW"
fi

echo "==> Signing app (SIGN_IDENTITY=$SIGN_IDENTITY)"
sign "$APP_BUNDLE"
```

Decisions:

- **Source of the framework.** It comes from `.build/release/Sparkle.framework`, the same copy the
  binary was linked against. The `.dSYM` next to it is not copied.
- **Re-sign everything.** Sparkle ships its framework, `Autoupdate`, and `Updater.app` signed
  ad-hoc with the `runtime` flag (`flags=0x10002(adhoc,runtime)`). Re-signing with `--force`
  replaces those signatures. Without `--preserve-metadata=flags` the runtime flag goes away, so the
  whole bundle ends up consistently ad-hoc without runtime. Leaving the vendor signatures in place
  would still pass `--verify --deep --strict`, which is why §2.8 adds explicit per-item checks.
- **No `--deep` when signing.** Sparkle's documentation warns against it, and inside-out signing is
  the supported method. `--deep` is only used for verification.
- **Removing the XPC services.** It drops about 400 KB, two nested bundles, and an entitlements
  dictionary on `Downloader.xpc` that would otherwise need `--preserve-metadata=entitlements`
  whenever it is re-signed. If the app is ever sandboxed, they come back, and the order becomes
  `Installer.xpc`, then `Downloader.xpc` (keeping its entitlements), then `Autoupdate`, then
  `Updater.app`, then the framework.
- **Path to #8.** This is the order Sparkle's documentation gives for manual signing, minus the
  XPC services. When #8 lands, it changes `CODESIGN_ARGS` once and every nested item gets the
  Developer ID identity, hardened runtime, and a timestamp. The app still loads Sparkle under
  library validation because everything then shares one team ID. `Autoupdate` and `Updater.app`
  need no entitlements when the app isn't sandboxed.
- **Zip.** The zip command becomes `ditto -c -k --sequesterRsrc --keepParent`, which is the form
  Sparkle's publishing documentation gives. It keeps symlinks, so the framework's signature
  survives. I checked the round trip.

### 2.4 Updater wiring and the footer

#### 2.4.1 `AppUpdater`

Sparkle annotates `SPUStandardUpdaterController`, `SPUUpdater`, and `SPUUpdaterDelegate` as
`NS_SWIFT_UI_ACTOR`, so they are main-actor types in Swift. `SPUStandardUserDriverDelegate` is not
annotated, so the conformance is declared `@preconcurrency`. Swift then inserts a main-actor
assertion at the boundary, and Sparkle calls its delegates on the main thread. `SPUUpdaterDelegate`
needs no `@preconcurrency`. The skeleton below compiles cleanly under Swift 6.4 in Swift 6 language
mode against Sparkle 2.10.0 (§2.10).

```swift
// Sources/Unlatch/AppUpdater.swift
import AppKit
import Observation
import Sparkle

/// Owns Sparkle's standard updater for the process lifetime. Created and
/// retained by AppDelegate. Sparkle holds its delegates weakly.
@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    let availability: UpdaterAvailability
    /// Mirrors SPUUpdater.canCheckForUpdates (KVO).
    private(set) var canCheckForUpdates = false
    /// A scheduled update alert is on screen and hasn't had the user's attention yet.
    private(set) var updateAvailable = false

    /// The footer's input: `updateButtonState(...)` over the three values above.
    var buttonState: UpdateButtonState {
        updateButtonState(
            availability: availability, canCheck: canCheckForUpdates, updateAvailable: updateAvailable)
    }

    /// Set by StatusItemController: close the popover before Sparkle shows a
    /// window, the same pattern as AppModel.onLoad.
    @ObservationIgnored var onWillPresent: (@MainActor () -> Void)?

    @ObservationIgnored private let shortVersion: String?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init(availability: UpdaterAvailability, shortVersion: String?)
    func checkForUpdates()

    // SPUUpdaterDelegate
    func allowedChannels(for updater: SPUUpdater) -> Set<String>

    // SPUStandardUserDriverDelegate (gentle reminders for a dockless app)
    var supportsGentleScheduledUpdateReminders: Bool { true }
    /// T8 (2026-10-15): always false, so Sparkle never shows a scheduled update by itself.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState)
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem)
    func standardUserDriverWillFinishUpdateSession()
}
```

Behaviour:

- **`init`.** When `availability != .enabled`, it returns without creating a controller, so nothing
  from Sparkle runs and no alert can appear. Otherwise it creates
  `SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self,
  userDriverDelegate: self)` and starts observing
  `controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new])`. Sparkle mutates
  that property on the main thread. The change handler reads `change.newValue ?? false` (a
  `Sendable` `Bool`) and writes it inside `MainActor.assumeIsolated`, the pattern
  `PopoverDismissalMonitor` and `StatusItemController` already use. It captures `self` weakly and
  does not send the `SPUUpdater` argument anywhere. Finally `init` calls
  `controller.startUpdater()`. Starting only after the observation is in place means the initial
  value isn't missed, and `SPUStandardUpdaterController` shows its own alert if starting fails.
- **`checkForUpdates()`.** Calls `onWillPresent?()` and then `controller?.checkForUpdates(nil)`.
  The popover has to close first. It's an `.applicationDefined` popover in a window level above
  normal windows, and `PopoverDismissalMonitor`'s global mouse monitor doesn't see clicks in
  Unlatch's own windows. Left open, it would cover Sparkle's update window. Both footer entry
  points, the menu item and the "Update Available" button, call this one method.
- **`allowedChannels(for:)`** returns `allowedUpdateChannels(forVersion: shortVersion)`. See §2.5.
- **Gentle reminders, with Sparkle's window suppressed (T8, maintainer decision 2026-10-15).**
  Gentle reminders are required for a dockless app, and Sparkle logs a warning without them.
  `supportsGentleScheduledUpdateReminders` stays `true`. New in T8,
  `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` returns
  `sparkleShowsScheduledUpdate(inImmediateFocus:)`, which is `false` for both values of
  `immediateFocus` (§2.5). Sparkle then owns no presentation of a scheduled update: it neither
  activates the app nor orders a window in, front or back. The delegate methods become one-liners
  over the pure reducer `updateIndicatorShown(after:current:)` (§2.5):
  - `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` applies
    `.willShowUpdate(handledBySparkle: handleShowingUpdate, userInitiated: state.userInitiated)`.
    The result is `true` whenever the check was not user-initiated, which with T8 always arrives
    with `handleShowingUpdate == false`. A user-initiated check leaves the value alone: Sparkle
    shows that update itself, in front, so there is nothing to remind about.
  - `standardUserDriverDidReceiveUserAttention(forUpdate:)` applies `.userAttention`, and
    `standardUserDriverWillFinishUpdateSession()` applies `.sessionFinished`. Both give `false`, as
    before.

  This is Sparkle's documented "delegate handles showing the update" mode
  (`SPUStandardUserDriverDelegate.h`, and sparkle-project.org/documentation/gentle-reminders),
  without the Dock badge and notification parts (non-goals). The behaviour below was confirmed
  against the gentle-reminders page and the Sparkle 2.10.0 sources pinned in `Package.resolved`
  (file and line references are to that release).
- **What Sparkle does when the delegate returns `false`** (`SPUStandardUserDriver.m`, lines
  176-333). The standard user driver still builds the update alert and keeps it, unshown, as its
  active alert. The update session stays open. It skips the activation, `showWindow`, and
  `orderBack` calls that the previous version of this design depended on, and it calls
  `standardUserDriverWillHandleShowingUpdate(false, …)` one run-loop turn later (lines 297-310).
  The near-launch rule (within about 3 seconds of the updater starting, lines 195-198) and the
  "app active with a key window" rule (lines 263-269) no longer matter for Unlatch: they only
  decide how Sparkle would have shown the window. So the indicator now behaves the same in every
  case: the scheduled check finds an update, and the footer button, the ellipsis dot, the menu
  item, and the status item dot appear, live if the popover is open.
- **`checkForUpdates()` presents the update already found.** `SPUUpdater.checkForUpdates`
  (`SPUUpdater.m`, lines 684-705) sees that the scheduled driver is showing an update and calls
  the user driver's `showUpdateInFocus` instead of starting a new check. That (lines 466-491)
  calls `setUpActiveUpdateAlertForScheduledUpdate:nil`, which activates the app if needed and
  shows the existing alert as key with the Install button focused (lines 183-192). The alert
  becoming key in an active app counts as attention, so `.userAttention` clears the indicator.
  No second feed request is made. The header confirms the intent: "To bring the update alert in
  focus, you may call `-[SPUStandardUpdaterController checkForUpdates:]`."
- **`canCheckForUpdates` and the indicator.** Per `SPUUpdater.h`, `canCheckForUpdates` stays `true`
  while an update is being shown. `SPUUpdater.m` (lines 894-897) sets it back to `true` as soon as
  the driver reports the update shown, which happens right after the alert is built, even though
  it is not on screen (`SPUUIBasedUpdateDriver.m`, lines 243-325). The delegate callback that sets
  `updateAvailable` comes a run-loop turn later, so `updateButtonState` reaches `.updateAvailable`.
  It is `false` while a feed or update downloads in the background, and `updateButtonState` then
  gives `.checkDisabled`, which also hides the indicator for that moment.

#### Lifecycle of a found update (T8)

| What happens | Result |
| --- | --- |
| Scheduled check finds an update, popover closed | No window, no activation. The status item dot appears. The footer indicator is there the next time the popover opens. |
| Scheduled check finds an update, popover open | No window. The footer button, the ellipsis dot, and the status item dot appear in place. The popover stays key. |
| Scheduled check right after launch (overdue check, near-launch window) | Same as above. Before T8 this case activated the app and showed Sparkle's alert in front. |
| User clicks "Update Available" or "Update Available…", popover open | `onWillPresent` closes the popover, then `checkForUpdates()` shows the found update in front as key. The app is already active. Attention clears every indicator, the status item dot included. |
| User only opens and closes the popover | Nothing changes. Clicking the status item never opens Sparkle's window; it only toggles the popover. |
| User never clicks | The session stays open for the life of the process. Sparkle schedules the next check only when a session ends (`SPUUpdater.m`, lines 502-503, 593-600, and 886-890), so there is no re-check the next day and no second alert. Sparkle has no escalation for an ignored, not-downloaded update: `SUScheduledImpatientCheckInterval` only applies to updates that were already downloaded, which `SUAllowsAutomaticUpdates = false` rules out. The indicator stays until the user acts or quits. |
| A newer release is published while an update is pending | The pending session still holds the older item. Clicking shows that item, and installing it installs that version. The next scheduled check, one interval after the session ends, offers the newer one. Accepted (§2.11). |
| "Remind Me Later", or closing the alert with its close button | Both are `SPUUserUpdateChoiceDismiss` (`SUUpdateAlert.m`, lines 490-494). The session ends and the indicator clears. The next scheduled check runs one interval (a day) after the session ended and, if the update is still there, brings the indicator back. |
| "Skip This Version" | The session ends and the indicator clears. Sparkle stores the version in `SUSkippedVersion` and filters it out of *scheduled* checks only (`SUAppcastDriver.m`, line 228), so no indicator returns for that version. "Check for Updates…" still offers it, and a newer version brings the indicator back. |
| "Install Update" | Downloads, installs, and relaunches. The new process starts with no indicator. |
| Quit or relaunch while an update is pending | The indicator is in-memory only, so it is gone after relaunch. Sparkle wrote `SULastCheckTime` when that check *started* (`SPUUpdater.m`, line 789), so the next scheduled check is about a day after it, and the indicator returns then, again without a window. "Check for Updates…" finds the update at any time. |
| The user declined automatic checks in the second-launch prompt | No scheduled checks, so no indicator ever. "Check for Updates…" still works. |

Lifetime, ownership, and isolation:

- **`AppDelegate`** gains `private var updater: AppUpdater?`, assigned once in
  `applicationDidFinishLaunching` and never cleared. It builds `AppUpdater(availability:
  updaterAvailability(bundleURL: Bundle.main.bundleURL, feedURL: info["SUFeedURL"] as? String,
  publicEDKey: info["SUPublicEDKey"] as? String), shortVersion:
  info["CFBundleShortVersionString"] as? String)` before `StatusItemController(model:updater:)`.
  `NSApplication.delegate` is weak, but `AppDelegate.main()` keeps its local `delegate` alive
  across `app.run()`, which never returns, so the delegate, the `AppUpdater`, and the
  `SPUStandardUpdaterController` it owns all live for the process. Nothing else holds the
  controller. Sparkle holds the `AppUpdater` only weakly, as both delegates.
- **`StatusItemController`** takes `init(model: AppModel, updater: AppUpdater)`, sets
  `updater.onWillPresent = { [weak self] in self?.closePopover() }`, renders the status item from
  both `model` and `updater` (T9, §2.4.3), and passes the updater to
  `PopoverHostingController(model:updater:)`, which passes it on to `PopoverView(model:updater:)` as
  a plain `let updater: AppUpdater`. SwiftUI tracks reads of an `@Observable` class without
  `@Bindable`.
- **Isolation.** Every type here is `@MainActor`: `AppDelegate`, `StatusItemController`,
  `AppUpdater`, the Sparkle types, and the SwiftUI view. The only boundary crossings are the KVO
  handler and Sparkle's calls into `SPUStandardUserDriverDelegate`, both on the main thread and
  handled by `assumeIsolated` and the `@preconcurrency` assertion respectively. Nothing
  Sparkle-related enters a detached task, and no `nonisolated(unsafe)` or `@unchecked Sendable` is
  needed.
- **`AppModel`, `UnlatchCore`, and the detached classify, verify, and save tasks** stay unchanged.
  Update state never mixes with flow state.

#### 2.4.2 The footer (option C, #57)

```
+--------------------------------------------+
| ● Update Available             (…)•  Quit ⏻ |   .updateAvailable: accent button on the left, dot on the ellipsis
|                                (…)   Quit ⏻ |   every other state: only the ellipsis and Quit
+--------------------------------------------+

Ellipsis menu:
  Version 1.1.0 (28)            disabled header item
  ---------------------------
  Check for Updates…            "Update Available…" when an update is found; hidden when the updater is unavailable
  ✓ Open at Login               checkmark item, shows the system login item state
```

The row stays one 26 pt high `HStack(spacing: 6)` with 14 pt horizontal padding, as today. The
version label and the Open at Login checkbox leave the row. Quit stays in the row, unchanged: the
"Quit" label plus the `power` symbol, ⌘Q, `.help("Quit Unlatch")`, the "Quit Unlatch"
accessibility label, and the hover highlight.

The footer reads `updater.buttonState`, maps it through the pure `updateFooterPresentation(for:)`
(§2.5), and renders:

| `UpdateButtonState` | Menu update item | "Update Available" button and dot |
| --- | --- | --- |
| `.hidden` (`swift run`, missing feed or key) | Not in the menu | Hidden |
| `.checkDisabled` | "Check for Updates…", disabled | Hidden |
| `.check` | "Check for Updates…", enabled | Hidden |
| `.updateAvailable` | "Update Available…" (§6 question 5), enabled | Shown, together with the status item dot (§2.4.3) |

Menu contents, in this order (#57). Nothing else goes in the menu:

1. **Version.** `Text(Self.versionText)`, the existing `versionLabel(version:build:)` string. SwiftUI
   renders a `Text` in a `Menu` as a disabled item.
2. **Separator.** `Divider()`.
3. **Update item.** `Button(title) { updater.checkForUpdates() }.disabled(!enabled)`, emitted only
   when `menuItemTitle` is non-nil. Under `swift run` the menu is version, separator, Open at Login.
4. **Open at Login.** `Toggle("Open at Login", isOn: Binding(get: { model.loginItem.isOn }, set:
   { model.setLaunchAtLogin($0) }))` with `.disabled(!model.loginItem.isEnabled)` and
   `.help(model.loginItem.help)`. A `Toggle` in a `Menu` is a checkmark item.

Sketch of the view code (the implementer owns the details):

```swift
private var footer: some View {
    let update = updateFooterPresentation(for: updater.buttonState)
    return HStack(spacing: 6) {
        if update.showsUpdateIndicator { updateAvailableButton }
        Spacer()
        moreMenu(update)
            .overlay(alignment: .topTrailing) { if update.showsUpdateIndicator { updateDot } }
        quitButton
    }
    .padding(.horizontal, 14)
    .frame(height: 26)
}
```

Details:

- **The ellipsis button.** `Image(systemName: "ellipsis.circle")` at 13 pt as the `Menu` label,
  padded with `.padding(.top, 4).padding(.trailing, 4)` as in the prototype
  (`FooterVariants.swift`, lines 211-212), with `.menuIndicator(.hidden)` and `.fixedSize()`. The
  padding gives the dot room at the top-trailing corner so it sits beside the glyph instead of on
  top of it. Use `.menuStyle(.button)` with
  `.buttonStyle(.borderless)`, the replacement Apple's interface names for `.borderlessButton`. If
  that renders differently from the prototype's screenshots, `.menuStyle(.borderlessButton)` (what
  the prototype used) is acceptable: it is soft-deprecated (`deprecated: 100000.0`) and produces no
  warning.
- **The dot.** A 7 pt accent `Circle` in an `.overlay(alignment: .topTrailing)` on the `Menu`, with
  `.allowsHitTesting(false)` and `.accessibilityHidden(true)` (its meaning is announced through the
  ellipsis button, see Accessibility below). It lands in the 4 pt padding of the label, so it must
  not cover any part of the `ellipsis.circle` glyph. It has to be outside the `Menu` label, because the `NSPopUpButton`
  behind the menu flattens its label to a template image and drops the colour (found by the
  prototype).
- **The "Update Available" button.** A plain button in the same style as Quit: 11 pt text, a 20 pt
  high hover capsule, the accent colour as foreground, and a 6 pt accent dot before the text. It is
  on the left of the row and calls `updater.checkForUpdates()`. Factor the shared hover-capsule
  styling out of `quitButton` into one private `ButtonStyle` or view in `PopoverView.swift`, so the
  two buttons can't drift. That is the only refactor of Quit.
- **`loginItemRevision` goes away.** The checkbox needed `.id(model.loginItemRevision)` because an
  `NSButton` checkbox flips itself on click, and `@Observable` doesn't notify when
  `loginItemStatus` is assigned an equal value, so nothing redrew it after a failed attempt. A menu
  item doesn't flip itself. **Verified during design** (macOS 27.0.1, throwaway SwiftUI package in
  `/tmp`): choosing a `Toggle` menu item whose binding setter leaves the model unchanged calls the
  setter with `true`, and the `NSMenuItem`'s state is still off right after the action and when
  the menu opens again. So the checkmark always shows `model.loginItem.isOn`, the real system
  state, and nothing needs to force a redraw. **Recommendation: T3 removes it.** Delete the
  `loginItemRevision` property and its bump in `refreshLoginItem()`, reword the doc comments on
  `refreshLoginItem()` and `setLaunchAtLogin(_:)` that mention the checkbox, and delete
  `revisionChanges(_:during:)` and the three tests built on it
  (`failedRegisterStillNotifiesObservers`, `openingSystemSettingsStillNotifiesObservers`,
  `refreshWithAnUnchangedStatusNotifiesObservers`). `appModelSnapsBackWhenRegisterFails` and the
  other state-based tests stay, and they still cover the snap-back. Keeping the property would
  leave observable state that nothing reads and a doc comment describing a control that no longer
  exists.
- **Behaviour of Open at Login is unchanged** (#51): checking registers, unchecking unregisters,
  checking in `.requiresApproval` opens System Settings > General > Login Items, a failure is
  logged, and `StatusItemController.presentAndFocus()` still refreshes the state each time the
  popover opens.
- **Escape and outside clicks while the menu is open.** Menu tracking runs its own event loop, and
  AppKit does not call local event monitors for events that menu tracking consumes, so Esc closes
  only the menu and `PopoverDismissalMonitor`'s Esc monitor doesn't fire. Clicks on menu items are
  in-process, so the global mouse-down monitor doesn't see them either. A T3 acceptance check
  confirms both.
- **Keyboard shortcuts.** None are added. ⌘Q stays the footer's only shortcut.

Accessibility:

| Element | VoiceOver label | Tooltip (`.help`) |
| --- | --- | --- |
| Ellipsis menu button | Label "More". Value "Update available" in `.updateAvailable`, otherwise no value | "More" |
| Dot | Not an element (`.accessibilityHidden(true)`). Its meaning is the ellipsis button's value | None |
| "Update Available" button | "Update Available" | "See the available update" |
| Menu items | Their titles. Open at Login is read with its checked state, the version as dimmed | Open at Login: `model.loginItem.help` |
| Quit | "Quit Unlatch", unchanged | "Quit Unlatch", unchanged |

In `.updateAvailable` there are two things to announce: the "Update Available" button, which is
the action, and the dot, which marks the ellipsis. The dot's VoiceOver label (#57) is carried as the
ellipsis button's accessibility value, so the ellipsis and its dot are one element that announces
the update once: "More, Update available, menu button". The "Update Available" button is the
separate element that performs the action. The prototype instead labelled the ellipsis "More,
update available". A separate overlay element for a 7 pt dot was rejected: whether SwiftUI exposes
an overlay on an `NSPopUpButton`-backed `Menu` as its own element is not guaranteed, and an
unreliable element is not testable. In every other state the ellipsis has no value and reads "More,
menu button".

With System Settings > Keyboard > Keyboard navigation on, Tab reaches "Update Available", the
ellipsis, and Quit. Space opens the menu, and the arrow keys and Return choose items. This is
standard `NSPopUpButton` behaviour and needs no code.

**Verified during design** (macOS 27.0.1, Xcode 27 SDK, throwaway package in `/tmp`): a SwiftUI
`Menu` with the content above produces these `NSMenuItem`s: the `Text` as a disabled item, the
`Divider` as a separator, `.help` on a `Button` as the item's `toolTip`, and a disabled `Toggle` as
a disabled item with `state == .on` that keeps its `toolTip`. So the explanation from
`loginItemControl(for:)` stays available as a tooltip under `swift run`, as #57 asks. A second
AppKit probe confirmed that macOS actually *shows* the tooltip on a disabled `NSMenuItem`: hovering
the disabled, checked "Open at Login" item displayed its tooltip window. Neither probe was run on
macOS 14; the T3 manual check covers the oldest macOS available to the maintainer.

#### 2.4.3 The status item dot (T9, maintainer decision 2026-10-15)

While an update is available, the menu bar icon gets a small dot at its top-trailing corner, so the
update is noticed without opening the popover. It appears and clears exactly with the footer's
indicator, because both read the same value:
`updateFooterPresentation(for: updater.buttonState).showsUpdateIndicator`, folded into
`statusItemPresentation(hasLockedWork:updateState:)` (§2.5).

```
normal:            [lock.open]       the template glyph, as today
update available:  [lock.open]•      the same glyph, a 6 pt dot at its top-trailing corner,
                                     separated from the glyph by a 1.5 pt transparent ring
```

**Rendering.** Today `StatusItemController.renderButton(hasLockedWork:)` sets
`NSImage(systemSymbolName: statusSymbolName(...), accessibilityDescription: "Unlatch")` with
`isTemplate = true`, re-armed by `withObservationTracking` in `observeModel()`. T9 changes this to:

```swift
// StatusItemController.swift (sketch; the implementer owns the details)
private func observeState() {
    withObservationTracking {
        render(statusItemPresentation(
            hasLockedWork: model.hasLockedWork, updateState: updater.buttonState))
    } onChange: { [weak self] in
        Task { @MainActor in self?.observeState() }
    }
}

private func render(_ presentation: StatusItemPresentation) {
    guard let button = statusItem.button,
          let symbol = NSImage(systemSymbolName: presentation.symbolName,
                               accessibilityDescription: StatusItemPresentation.accessibilityLabel)
    else { return }
    let image = presentation.showsUpdateBadge ? Self.badged(symbol) : symbol
    image.isTemplate = true
    button.image = image
    button.toolTip = presentation.toolTip
    button.setAccessibilityLabel(StatusItemPresentation.accessibilityLabel)
    button.setAccessibilityValue(presentation.accessibilityValue)
}

/// The symbol with a dot at its top-trailing corner, separated from the glyph by a transparent
/// ring. Same size and alignment rect as the symbol, so the icon doesn't move when the dot comes
/// and goes. Stays a template image: AppKit tints it for light, dark, and tinted menu bars and
/// for the pressed highlight.
/// `nonisolated`: AppKit may call an NSImage drawing handler on any thread (NSImage.h), and the
/// handler isn't `@Sendable`, so inside a main-actor method it would inherit main-actor isolation.
nonisolated private static func badged(_ symbol: NSImage) -> NSImage {
    let diameter: CGFloat = 6, ring: CGFloat = 1.5
    let image = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter,
                         width: diameter, height: diameter)
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: dot.insetBy(dx: -ring, dy: -ring)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        NSBezierPath(ovalIn: dot).fill()
        return true
    }
    image.alignmentRect = symbol.alignmentRect
    image.accessibilityDescription = symbol.accessibilityDescription
    return image
}
```

The one tracking closure reads `model.hasLockedWork` and `updater.buttonState`. Both are
`@MainActor @Observable`, so a change to either re-renders the icon. `configureStatusItem()` stops
setting `toolTip`, because `render` now owns it. The rest of the button (target, action,
`sendAction(on:)`, and the highlight monitor) is unchanged.

**Verified during design** (Swift 6.4, Xcode 27.0, macOS 27 SDK, deployment target 14, throwaway
package in `/tmp`): the `badged(_:)` function above compiles in Swift 6 language mode with no
warnings. (The design probe compiled it as a `@MainActor` function; review of PR #66 found that
variant unsafe at run time and verified the `nonisolated` form clean, see Isolation below.) It
produces a 17 × 15 pt template image for `lock.open`,
the same size as the symbol, which reports an alignment rect of (0, 2.5, 16.5, 9). That is why the
composite copies `alignmentRect`. A drawing-handler image would otherwise report its full bounds
and could shift the glyph vertically in the menu bar. The exact dot size and position against the
`lock` and `lock.open` glyphs at 1x and 2x is a T9 manual check: the dot must not merge with the
shackle, and the ring must keep a visible gap.

**Template, not colour.** The dot is the same colour as the glyph: black or white for the menu
bar, inverted with the pressed highlight. An accent-blue dot would need a non-template image,
which AppKit no longer adapts to light, dark, and tinted menu bars or the highlight (§3.10). The
maintainer chose the template dot on 2026-10-15 (§6).

**Accessibility.**

| State | VoiceOver label | Value | Tooltip |
| --- | --- | --- | --- |
| No update (any lock state) | "Unlatch" | None | "Unlatch" |
| Update available | "Unlatch" | "Update available" | "Unlatch: update available" |

The value matches the ellipsis button's value in the footer, so VoiceOver uses the same words in
both places ("Unlatch, Update available"). The label stays "Unlatch", as today. The lock state is
not announced today and T9 doesn't add it.

**Isolation.** `StatusItemController`, `AppUpdater`, `AppModel`, and the tracking closure (whose
`onChange` hops back with `Task { @MainActor in … }`, as now) stay on the main actor. The image's
drawing handler is the exception. `NSImage(size:flipped:drawingHandler:)` documents that AppKit may
run the handler on any thread (NSImage.h, line 117), and the closure parameter isn't `@Sendable`.
Written inside a member of the `@MainActor` `StatusItemController`, the closure would therefore be
main-actor isolated. Swift 6 then inserts an executor check, and drawing off the main thread logs
"data race detected: @MainActor function … not called on the main thread" at run time. The review
of PR #66 reproduced this. So `badged(_:)` is `nonisolated private static`: the closure it creates
is nonisolated and only touches the captured symbol image, `NSGraphicsContext.current`,
`NSBezierPath`, and `NSColor`, all of which are safe in a drawing context on any thread. The
reviewer verified that form clean. `render(_:)` stays main-actor and calls it synchronously.

### 2.5 Pure helpers (`Logic.swift`)

Everything in the first block below is already on `main` (T2, #54) with its tests. T3 builds on it
and doesn't change it. T3 adds only the second block.

```swift
/// Whether this process can run Sparkle at all.
enum UpdaterAvailability: Equatable, Sendable {
    case enabled
    case disabled(UpdaterDisabledReason)
}

enum UpdaterDisabledReason: Equatable, Sendable {
    /// `swift run`, the test runner: Bundle.main is not an .app, so there is
    /// no Info.plist and Sparkle would fail to start ("does not have a valid
    /// bundle identifier") and show an error alert on every launch.
    case notAnAppBundle
    case missingFeedURL
    /// Anything other than an https URL.
    case insecureFeedURL
    case missingPublicKey
}

/// Checks run in order. Empty strings count as missing.
func updaterAvailability(bundleURL: URL, feedURL: String?, publicEDKey: String?) -> UpdaterAvailability

/// `["beta"]` when the running build is itself a beta (its
/// CFBundleShortVersionString contains "-beta.", including `git describe`
/// forms such as "1.1.0-beta.2-3-gabc1234"). Otherwise `[]`, meaning the
/// default channel only. Sparkle always includes the default channel, so
/// beta builds see stable releases too.
func allowedUpdateChannels(forVersion shortVersion: String?) -> Set<String>

enum UpdateButtonState: Equatable, Sendable {
    case hidden, checkDisabled, check, updateAvailable
}

/// .hidden unless availability is .enabled. With canCheck false, the result
/// is .checkDisabled, even when updateAvailable is true. Otherwise
/// updateAvailable selects .updateAvailable and anything else gives .check.
func updateButtonState(
    availability: UpdaterAvailability, canCheck: Bool, updateAvailable: Bool
) -> UpdateButtonState
```

T3 adds the mapping from that state to the footer of #57, so the copy and the visibility rules are
unit-tested instead of living only in the view:

```swift
/// What the popover footer shows for the updater (option C, #57).
struct UpdateFooterPresentation: Equatable, Sendable {
    /// The update item in the ellipsis menu. `nil` leaves it out of the menu.
    let menuItemTitle: String?
    let menuItemEnabled: Bool
    /// The accent "Update Available" footer button and the dot on the ellipsis button.
    let showsUpdateIndicator: Bool

    static let checkTitle = "Check for Updates…"
    /// Confirmed by the maintainer on 2026-10-14 (§6 question 5).
    static let updateAvailableTitle = "Update Available…"
}

/// .hidden: no item, no indicator. .checkDisabled: checkTitle, disabled, no indicator.
/// .check: checkTitle, enabled, no indicator. .updateAvailable: updateAvailableTitle, enabled,
/// indicator shown.
func updateFooterPresentation(for state: UpdateButtonState) -> UpdateFooterPresentation
```

The copy lives in the two `static let`s, so the pending wording decision changes one line and one
test. The footer button's own title, "Update Available", is fixed by #57 and stays in the view.

T8 adds the scheduled-update decisions of 2026-10-15, so `AppUpdater`'s delegate methods hold no
logic of their own:

```swift
/// What Sparkle's standard user driver reports about the update on offer.
enum UpdateReminderEvent: Equatable, Sendable {
    /// standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)
    case willShowUpdate(handledBySparkle: Bool, userInitiated: Bool)
    /// standardUserDriverDidReceiveUserAttention(forUpdate:)
    case userAttention
    /// standardUserDriverWillFinishUpdateSession()
    case sessionFinished
}

/// Maintainer decision 2026-10-15: Sparkle never shows a scheduled update by itself, not even in
/// immediate focus. The in-app indicator is the only reminder. Always false.
func sparkleShowsScheduledUpdate(inImmediateFocus immediateFocus: Bool) -> Bool

/// The next value of AppUpdater.updateAvailable. .willShowUpdate with userInitiated false gives
/// true, whatever handledBySparkle says. .willShowUpdate with userInitiated true keeps `current`
/// (Sparkle shows that update itself, in front). .userAttention and .sessionFinished give false.
func updateIndicatorShown(after event: UpdateReminderEvent, current: Bool) -> Bool
```

The reducer is deliberately not named `updateAvailable(…)`: inside `AppUpdater`, unqualified
lookup would find the `updateAvailable` property first and fail to compile.

T9 adds the status item's presentation next to `statusSymbolName(hasLockedWork:)`, which it uses:

```swift
/// What the menu bar status item shows (Design/sparkle-updates.md §2.4.3).
struct StatusItemPresentation: Equatable, Sendable {
    /// statusSymbolName(hasLockedWork:): "lock" or "lock.open".
    let symbolName: String
    /// The dot on the icon. Same condition as the footer's indicator.
    let showsUpdateBadge: Bool
    /// nil, or updateAvailableValue.
    let accessibilityValue: String?
    let toolTip: String

    static let accessibilityLabel = "Unlatch"
    static let updateAvailableValue = "Update available"
    static let updateAvailableToolTip = "Unlatch: update available"
}

/// showsUpdateBadge is updateFooterPresentation(for: updateState).showsUpdateIndicator, so the
/// icon and the footer can't disagree. With the badge: accessibilityValue updateAvailableValue
/// and toolTip updateAvailableToolTip. Without: nil and "Unlatch".
func statusItemPresentation(
    hasLockedWork: Bool, updateState: UpdateButtonState
) -> StatusItemPresentation
```

`AppDelegate` reads `Bundle.main.bundleURL`, `SUFeedURL`, `SUPublicEDKey`, and
`CFBundleShortVersionString` from `Bundle.main.infoDictionary` and passes in plain values. That
keeps these helpers free of `Bundle` and unit-testable.

**Beta channel policy.** Beta builds follow the beta channel, and stable builds don't. This needs
no settings UI, matches who installs a beta (someone who chose to test), and lets the N → N+1
upgrade test run on two betas instead of on users (§4). One consequence: a tester stays on the
beta channel until they install a stable build that has a higher build number than their beta.
They also get offered stable releases in the meantime, so they never get stranded.

### 2.6 Appcast hosting, channels, and the same-build trap

**Hosting.** The appcast is published on GitHub Pages, deployed by Actions (not from a `gh-pages`
branch):

- `SUFeedURL` = `https://pablocolaiacovo.github.io/unlatch/appcast.xml`
- Enclosure URLs = `https://github.com/pablocolaiacovo/unlatch/releases/download/<tag>/Unlatch.zip`.
  These are release assets, with notes and binaries kept where they are today.

The repository is public, so Pages costs nothing. §3.1 explains why this beats a release asset.

**Feed state.** An Actions-deployed Pages site is replaced as a whole on every deploy. The
`appcast` job therefore fetches the live feed first, with `curl` and a cache-busting query string:

- **200:** use the feed as the base.
- **404:** start a new feed and emit a `::warning::`. This is expected on the first Sparkle release.
  If it happens later, the only loss is older items, and the newest item, the one that matters, is
  regenerated anyway.
- **Any other status:** fail the job. A transient error must never quietly reset the feed.

`generate_appcast` keeps existing items even when their archives aren't present, so the job only
needs the new zip (verified, §2.10).

> **Superseded by #77 (and #78).** The paragraph below describes the flow as designed, with a
> stable tag on its last beta's commit. Pages dedupes deploys on the commit SHA, so that flow
> left v1.1.0's feed unchanged (#76). RELEASING.md step 4 now puts a stable tag on a different
> commit, so it has its own build number, and `release.yml` refuses a tag whose commit another tag
> already deployed, before `publish`. `appcast-drop-build.xsl` stays as a defensive step.

**The same-build trap (found while verifying this design).** `CFBundleVersion` is
`git rev-list --count HEAD`. When `v1.2.0` is tagged on the same commit as `v1.2.0-beta.2`, which
is the normal outcome of RELEASING.md's beta step, both builds have the same `CFBundleVersion`.
`generate_appcast` matches items by version. It *updates the existing beta item in place*: it
swaps the enclosure to the stable zip but keeps the beta title, the `<sparkle:channel>beta`
element, and the beta notes. Stable users would never be offered that release. The fix is to
delete any existing `<item>` whose `sparkle:version` equals the new build number before calling
`generate_appcast`. `Scripts/appcast-drop-build.xsl` does this with `xsltproc`, which ships with
macOS, through an identity transform with `cdata-section-elements="description"` so embedded notes
stay in CDATA. The template has to use `xsl:if` inside `match="item"`, because XSLT 1.0 doesn't
allow variables in match patterns. Users still on that beta build aren't affected: the stable
build carries the same code and build number, so nothing is offered to them, which is correct.

**Changing `CFBundleVersion`'s scheme was rejected.** Encoding beta versus stable into the build
number would mean changing a scheme that v1.0.0 already shipped. It would add arithmetic that
every future release relies on, to fix a problem that a single stripping step solves.

### 2.7 Generating and signing the appcast in CI

Sparkle's tools are macOS-only, and the private key should only be exposed to a job that runs no
third-party build code. That rules out putting this in `build-and-package`, which runs
`swift build` and with it Sparkle's package manifest, and it rules out the Linux `publish` job.
`release.yml` gets two new jobs, both gated on `github.event_name == 'push'` like `publish`:

```
build-and-package (xcode-27)  ->  publish (ubuntu-24.04)  ->  appcast (xcode-27)  ->  deploy-feed (ubuntu-24.04)
                                   gh release create           sign + generate           Pages deploy
```

Running the feed *after* `publish` means the feed never points at an asset that doesn't exist yet.
If `appcast` or `deploy-feed` fails, the release exists but isn't announced in the app yet.
Re-running is not idempotent for every job: recover with **Re-run this job** on `appcast`, never
**Re-run all jobs**, and only within 30 days of the original run. The full procedure, including why
**Re-run failed jobs** is wrong when only `deploy-feed` failed, is in `RELEASING.md` step 5 and the
header of `release.yml`.

**`appcast`** job:

- `runs-on: xcode-27`, with the same `DEVELOPER_DIR` pin as the existing jobs.
- `environment: sparkle-signing`. The secret is scoped to this environment, and the environment is
  restricted to `v*` tags (§2.9).
- `permissions: contents: read`, and `concurrency: { group: appcast, cancel-in-progress: false }`
  at job level. That serializes feed updates across tags, which the per-ref group at workflow level
  doesn't do.
- Steps:
  1. `actions/checkout` (depth 1 is enough), then `swift package resolve`. The tools come from
     `.build/artifacts/sparkle/Sparkle/bin`, the version pinned in `Package.resolved` and checked
     against the binary target's checksum by SwiftPM. No second version pin goes in the workflow.
  2. Download `Unlatch.zip` from the published release with `gh release download`, not the 7-day
     `unlatch-zip` build artifact, so a late re-run still works. Fail unless the asset has a
     `sha256:` digest in the GitHub API and the downloaded file's `shasum -a 256` matches it.
  3. Release notes: `gh release view "$TAG" --json body --jq .body`. Delete the
     `<!-- Release notes generated … -->` comment line and write the result to `Unlatch.md` next to
     the zip. `generate_appcast` picks up a `.md` file with the same base name as the archive, and
     `--embed-release-notes` embeds it as `<description sparkle:format="markdown">`. Sparkle 2.9+
     renders basic Markdown on macOS 12+. These are the same PR-title notes the release page shows,
     so there's one source of truth.
  4. Fetch the live feed as §2.6 describes. The feed URL is `SUFeedURL` read from the zip's
     `Info.plist`. That URL and the bundle's `CFBundleVersion` become job outputs for `deploy-feed`.
  5. Run `Scripts/update-appcast.sh`, below.
  6. Upload `appcast.xml` as the `appcast` artifact, with `overwrite: true` so a re-run of the job
     can upload it again.

**`deploy-feed`** job:

- `runs-on: ubuntu-24.04`, with `needs: appcast`.
- `environment: { name: github-pages, url: ${{ steps.deploy.outputs.page_url }} }`.
- `permissions: { pages: write, id-token: write }`.
- Steps: download the artifact, then re-fetch the live feed and fail if the artifact lacks a live
  item, by `sparkle:version` and channel. The only exception is the build `appcast` replaced moving
  from beta to stable. A 404 means there is no feed yet. This stops a re-run of an older tag's
  deploy from rolling the feed back, because the `appcast` concurrency group doesn't cover this
  job. Then `actions/upload-pages-artifact` and `actions/deploy-pages`.
  `devops` pins the current major versions when implementing. They are a separate Linux job
  because `upload-pages-artifact` tars with GNU tar flags.

**`Scripts/update-appcast.sh`** is the publishing logic in one script, so `devops` can run it
locally with a throwaway key (§4). Interface:

```
Scripts/update-appcast.sh --zip <Unlatch.zip> --notes <notes.md> --tag <vX.Y.Z[-beta.N]> \
                          --current-feed <appcast.xml or empty> --out <dir>
# Private key: read from the SPARKLE_ED_PRIVATE_KEY environment variable and
# piped to the tools on stdin. It is never written to disk and never passed as
# an argument.
```

What it does:

1. Unzip the archive to a temporary directory. Read `CFBundleVersion`, `CFBundleShortVersionString`,
   `SUPublicEDKey`, and `SUFeedURL` with PlistBuddy. Fail if the short version doesn't equal the
   tag minus its leading `v`.
2. Set the channel to `beta` if the tag matches `*-beta.*`, and to nothing otherwise.
3. If there is a current feed, apply `appcast-drop-build.xsl` with `--stringparam build
   <CFBundleVersion>` and write the result to `<work>/appcast.xml`. Writing to a temporary file and
   then moving it, with `set -euo pipefail`, matters here: a failed transform otherwise leaves an
   empty file, and `generate_appcast` fails on it with "zero length data", which I reproduced.
4. Copy the zip and notes into the work directory as `Unlatch.zip` and `Unlatch.md`.
5. Run:
   ```
   printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - \
     --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
     --link "https://github.com/$REPO/releases" \
     --embed-release-notes --maximum-deltas 0 ${CHANNEL:+--channel "$CHANNEL"} \
     -o "$WORK/appcast.xml" "$WORK" 2>&1 | tee "$WORK/generate.log"
   ```
6. Validate, and fail on any of these:
   - **Key mismatch.** `generate.log` contains `does not match`. `generate_appcast` only *warns*
     when the bundle's `SUPublicEDKey` doesn't match the signing key, and still exits 0 (verified).
     A mismatched key would ship updates that every installed copy rejects.
   - `xmllint --noout` fails.
   - The feed doesn't have exactly one item whose `sparkle:version` equals the build number.
   - That item's enclosure URL doesn't end in `/$TAG/Unlatch.zip`, or it has no `sparkle:edSignature`.
   - That item's channel isn't the expected one.
   - `sparkle:minimumSystemVersion` isn't `14.0`. `generate_appcast` infers it from
     `LSMinimumSystemVersion`.
7. Copy `appcast.xml` to `--out`. Nothing else is published: there are no `old_updates/` and no
   deltas.

**Secret name:** `SPARKLE_ED_PRIVATE_KEY`. It holds the base64 seed that `generate_keys -x` exports.

### 2.8 Release-workflow verification in `build-and-package`

These are added to the existing "Verify signature" and "Verify zip round-trip" steps. Each item
below is a check in ad-hoc mode. #8 flips the Authority and runtime assertions.

- `codesign --verify --deep --strict --verbose=2 dist/Unlatch.app`. This already exists.
- `Contents/Frameworks/Sparkle.framework` exists. `Contents/Frameworks/Sparkle.framework/XPCServices`
  does not.
- For the framework, `Versions/B/Autoupdate`, and `Versions/B/Updater.app`, check three things:
  - `codesign --verify --strict` passes.
  - `codesign -dv` reports `Signature=adhoc` and no `Authority=` line.
  - The `flags=` field doesn't contain `runtime`. This catches a vendor signature that was never
    replaced.
- The `Info.plist` has an `https://` `SUFeedURL` and a non-empty `SUPublicEDKey`, and has no
  `SUEnableInstallerLauncherService`.
- **Launch check.** On the round-tripped copy (what users get), start
  `"$ROUNDTRIP/Unlatch.app/Contents/MacOS/Unlatch" &`, wait 5 s, and assert with `kill -0` that it
  is still running, then kill it. A missing or unloadable framework makes dyld abort immediately
  with exit 134 and `Library not loaded: @rpath/Sparkle.framework/...`, which I reproduced.
  Sparkle makes no network request on a first launch. Its automatic checks wait for the user's
  answer to the second-launch prompt. If the hosted runner can't sustain a GUI process, use a
  static fallback instead, and record the reason in the workflow comment:
  - `otool -l` shows the `@executable_path/../Frameworks` rpath.
  - `Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle` exists.

### 2.9 One-time maintainer setup (human-only)

Only the maintainer can do these. No agent can or should do them. Steps 1 and 2 must happen before
Task 2 merges, because the public key goes into the template. Steps 3 to 5 must happen before the
first tag that includes Task 4.

1. **Generate the key pair.** Do this on the maintainer's Mac, in the login keychain.
   ```sh
   cd "$(mktemp -d)"
   curl -fsSLO https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz
   shasum -a 256 Sparkle-2.10.0.tar.xz
   # expect c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
   tar xf Sparkle-2.10.0.tar.xz
   ./bin/generate_keys --account unlatch
   # Prints the SUPublicEDKey value. Hand that string (public, safe to share)
   # to the Task 2 PR.
   ```
2. **Export and back up the private key.**
   ```sh
   ./bin/generate_keys --account unlatch -x ~/unlatch-sparkle-ed25519.key
   ```
   Store the file's contents in the maintainer's password manager. Ad-hoc builds have no Apple
   code-signing fallback in Sparkle's validator (§3.5), so **losing this key strands every installed
   copy**. Each user would have to reinstall by hand.
3. **Create the signing environment and secret.**
   ```sh
   gh api -X PUT repos/pablocolaiacovo/unlatch/environments/sparkle-signing \
     -F 'deployment_branch_policy[protected_branches]=false' \
     -F 'deployment_branch_policy[custom_branch_policies]=true'
   gh api -X POST repos/pablocolaiacovo/unlatch/environments/sparkle-signing/deployment-branch-policies \
     -f name='v*' -f type=tag
   gh secret set SPARKLE_ED_PRIVATE_KEY --env sparkle-signing --repo pablocolaiacovo/unlatch \
     < ~/unlatch-sparkle-ed25519.key
   rm ~/unlatch-sparkle-ed25519.key
   ```
4. **Enable Pages, built by Actions.**
   ```sh
   gh api -X POST repos/pablocolaiacovo/unlatch/pages -f build_type=workflow
   ```
5. **Let `v*` tags deploy to `github-pages`.** Enabling Pages creates the `github-pages`
   environment, which by default only lets `main` deploy. A tag-triggered run would otherwise fail
   with "Tag … is not allowed to deploy to github-pages due to environment protection rules".
   ```sh
   gh api -X POST repos/pablocolaiacovo/unlatch/environments/github-pages/deployment-branch-policies \
     -f name='v*' -f type=tag
   ```
   If that call is rejected because the environment uses "protected branches" mode, switch it to
   custom policies with the `PUT` from step 3, add `main` back as a branch policy, then repeat this
   call. The same setting is in the UI under Settings > Environments > github-pages > Deployment
   branches and tags.

### 2.10 Verified during design (Swift 6.4, Xcode 27.0, this Mac)

I checked these with throwaway packages in `/tmp`. The repository was not touched.

- The universal release build leaves `.build/release/Sparkle.framework` as a universal (arm64 and
  x86_64) framework, linked as `@rpath/Sparkle.framework/Versions/B/Sparkle`.
- **SwiftPM adds `@loader_path` to every executable's rpath by itself.** This corrects an earlier
  claim in this document. Verified on Xcode 27.0 (27A266a) and Swift 6.4, the toolchain CI pins, for
  debug and universal release builds, and on `main` with no Sparkle. An explicit
  `-Xlinker -rpath -Xlinker @loader_path` produces `ld: warning: duplicate -rpath '@loader_path'
  ignored`, so only `@executable_path/../Frameworks` is added. Re-add the `@loader_path` flag only
  if a future toolchain stops adding it.
- A remote (`file://` git) consumer of a library product builds even though the package's
  executable target has `unsafeFlags`. Sparkle is still cloned and its artifact downloaded.
- Inside-out ad-hoc signing (`Autoupdate`, `Updater.app`, framework, app) with the XPC services
  removed works:
  - `codesign --verify --deep --strict` passes.
  - The bundle survives a `ditto --sequesterRsrc` zip round trip.
  - Launched from the bundle, `SPUUpdater.start()` succeeds, the feed URL is read from
    `Info.plist`, and the framework is loaded from `Contents/Frameworks`.
- Under `swift run`, `start()` fails with "Sparkle cannot target a bundle that does not have a
  valid bundle identifier". That's why `.notAnAppBundle` exists.
- `generate_appcast` 2.10.0, run with a throwaway key through `--ed-key-file -`:
  - The channel item, the embedded Markdown notes, and the `minimumSystemVersion` inference all
    work.
  - Old items are kept without their archives.
  - Same-build in-place update (the trap in §2.6), and the `xsltproc` fix for it.
  - Key mismatch: it warns and exits 0.
- The `AppUpdater` skeleton in §2.4.1 builds without warnings in Swift 6 mode. Without
  `@preconcurrency`, the `SPUStandardUserDriverDelegate` conformance is an error ("crosses into
  main actor-isolated code").

### 2.11 Edge cases

- **`swift run` and tests.** Availability is `.notAnAppBundle`. The update menu item, the "Update
  Available" button, and the dot are hidden, no Sparkle object is created, and no alert appears.
  The ellipsis menu still shows the version, the separator, and Open at Login, which is disabled
  and explains why in its tooltip.
- **Locally packaged builds (`0.0.0-<sha>`).** They have the real feed and key, so they can be
  offered a stable release whose build number is higher. That's harmless.
- **Feed unreachable or offline.** A manual check shows Sparkle's error alert. Scheduled checks fail
  quietly.
- **Scheduled update found (T8).** Sparkle shows no window. The footer indicator and the status
  item dot are the only signal until the user clicks. The full lifecycle (ignore, Remind Me Later,
  Skip, relaunch, a newer release while pending) is the table in §2.4.1.
- **A newer release published while an update is pending.** The open session keeps offering the
  older item until the user acts, because Sparkle doesn't re-check during a session. Installing it
  is still an upgrade, and the next daily check offers the newer release. Accepted: Sparkle has no
  public API to drop a pending session, and releases are rare.
- **Check interval overrides.** Sparkle reads `SUScheduledCheckInterval` from user defaults before
  the Info.plist (`SPUUpdaterSettings.m`, lines 255-264, and `SUHost.m`, lines 395-398), so the
  `defaults write` in the upgrade test overrides the template's 86400, and
  `defaults delete` restores it. Sparkle enforces a one-hour minimum in release builds.
- **App translocation.** Sparkle can't update a copy running from a translocated (quarantined,
  never-moved) location. The README already says to drag the app to `/Applications`. The upgrade
  test installs it there.
- **An update while a save is running.** "Install and Relaunch" terminates the app. Both `unlock`
  and `executeSaveJob` write to a temporary file and then replace atomically, so an interrupted
  save leaves the original untouched. That's acceptable for v1.1, and no relaunch postponement is
  added.
- **A release deleted after publishing** (RELEASING.md's fix-forward rule). Its feed item points at
  a deleted asset until the `+1` hotfix's feed job publishes a newer item. Users who check in
  between get a download error, which is accepted. RELEASING.md should say so (Task 7).
- **Two tags pushed within about 10 minutes.** The `appcast` concurrency group doesn't cover
  `deploy-feed`, and Pages' CDN can serve a stale feed despite the cache-busting query string, so
  one run can build its feed without the other release's item. `update-appcast.sh` doesn't catch
  this: it only checks that the items of the feed it was given are kept. `deploy-feed` does: it
  re-fetches the live feed right before deploying and refuses if a live item would be dropped or
  demoted. The expected worst case is a failed `deploy-feed`, with that release not yet announced
  in the app, fixed by **Re-run this job** on that run's `appcast` (`RELEASING.md` step 5). Only if
  `deploy-feed`'s own fetch doesn't yet show the other release (a stale CDN copy, or the other
  run's Pages deploy still in flight, where the last deploy wins) can an item be lost. That loss is
  silent, with every job green, so the `RELEASING.md` step 5 live-feed check, run for both tags once
  both runs have finished, is what catches it. Re-running that tag's `appcast` within 30 days
  restores it.
- **Key rotation.** Rotation is still possible while the old key exists: ship an update signed with
  the old key that contains the new public key. Losing the key is the case that can't be recovered
  while signing is ad-hoc.
- **v1.0.0 users** update by hand once. The release notes and README say so.

## 3. Trade-offs

### 3.1 GitHub Pages versus a release asset for the feed

`releases/latest/download/appcast.xml` needs no setup, but it has three problems:

- "latest" excludes prereleases, so betas can never reach anyone in-app. The first in-app upgrade
  anyone could test would then be a stable release, which contradicts RELEASING.md's "betas first"
  rule.
- Each release's asset is a frozen snapshot, so fixing a bad feed means re-uploading assets on an
  already-published release. If the maintainer ever turns on GitHub's immutable releases, that's
  impossible.
- The URL depends on GitHub's "Latest" marker.

Pages costs two one-time settings (§2.9 steps 4 and 5) and gives a fixed URL that every shipped
binary keeps forever, channel support, and redeployable fixes. **Pages wins.** A `gh-pages`
branch was rejected because the workflow would push bot commits to the repository, and git state
should only change through PRs.

### 3.2 Betas: separate feed, channel, or excluded

- A separate `appcast-beta.xml` would need a second feed URL, chosen at runtime, with the same
  logic as channels but more files.
- Excluding betas leaves the upgrade path untested until a stable release (see 3.1).
- **Channels in one feed** is what Sparkle 2 is designed for, and the policy needs no UI (§2.5).

### 3.3 Where signing runs

Signing could run in `build-and-package`. That would be one fewer macOS job, but it would expose
the key to a job that executes dependency manifests and compiles code. A separate `appcast` job,
gated by an environment, costs about 1 to 2 macOS minutes per release and keeps the key away from
build code and from `workflow_dispatch` runs on branches. **A separate job wins.** An environment
secret beats a plain repository secret for the same reason.

### 3.4 Sparkle as a package-level dependency

A dependency in the root package is visible to everyone who resolves the package, including
`UnlatchCore` library consumers. They download Sparkle but never link it. To avoid that, the app
would have to move into its own package, a nested `App/Package.swift` depending on `..` by path.
That is a restructure touching CI, `package-app.sh`, and the docs. **Accept the cost for now.**
Revisit it if a library consumer complains.

### 3.5 Trust model under ad-hoc signing

Sparkle's validator, `SUUpdateValidator`, accepts an update when the EdDSA signature checks out
against the *installed* app's key **or** when the new app's code signature satisfies the old app's
designated requirement. An ad-hoc requirement is the cdhash, which never matches across versions,
so EdDSA is the only trust anchor. Once EdDSA passes, the new app only needs a *valid* signature of
any identity. That means the move to Developer ID in #8 works seamlessly as long as the EdDSA key
stays the same.

### 3.6 Signed feeds, deferred

`SURequireSignedFeed` (Sparkle 2.9+) together with `SUVerifyUpdateBeforeExtraction` would also sign
the feed and the notes. `generate_appcast` would handle this automatically. It's deferred because:

- The feed is served over HTTPS from Pages, so changing it requires write access to the repository.
- The archive is already EdDSA-signed, and that is what protects installs.
- Every shipped build would then require every future feed to be signed, which raises the cost of
  any manual repair.

It can be turned on in any later release without affecting older installs.

### 3.7 Keeping or removing the XPC services

Keeping them gives future sandboxing for free, but costs two more bundles to sign, an entitlements
dictionary to preserve, and about 400 KB. Sparkle explicitly allows removing them in
non-sandboxed apps. **Remove them.**

### 3.8 Footer layout for the update control (#57)

Four layouts were prototyped with live screenshots on `explore/footer-options`. A single row with
all four controls truncates the update button to "Updat…ailable" even before localisation. Two rows
show everything but make every step 26 pt taller. Turning the version label into the update link
is cheap but hard to discover and non-standard for VoiceOver. **The maintainer chose the ellipsis
menu on 2026-10-09 (option C)**: the footer keeps one row, a future item is one more menu row, and
the only coloured thing in the footer is the update prompt when there is one. The accepted costs
are that the version is no longer visible at a glance and Open at Login is one click deeper.

### 3.9 Who presents a scheduled update (decided 2026-10-15)

- **Let Sparkle show it (the T3 behaviour).** Sparkle's default for background apps. Its window
  either appears in front right after launch, which interrupts whatever the user is doing at login,
  or goes behind other apps, where it is easy to miss and still steals a window slot. The footer
  indicator only survived in some of those cases (the old §2.4.1 case list).
- **Return `immediateFocus`** (Sparkle's sample): Sparkle shows the window only in the near-launch
  case and the app handles the rest. That still pops a window at login, which is what the
  maintainer wanted to avoid.
- **Always return `false` (chosen).** The update waits behind an indicator the user controls, in
  the popover and on the menu bar icon. One rule, no timing-dependent cases, and the existing
  `checkForUpdates()` path brings the update forward with no new Sparkle API. The cost is that an
  update the user never looks at is never forced on them, and there is no escalation. For an app
  that decrypts local PDFs and has no security-critical network surface, that is acceptable.

### 3.10 How the status item shows the dot

- **Composite template image (chosen).** One `NSImage` drawn from the SF Symbol plus a knocked-out
  dot, `isTemplate = true`. AppKit keeps handling light, dark, and tinted menu bars, the pressed
  highlight, and Increase Contrast. About 20 lines, no new view, verified to compile in Swift 6
  mode (§2.4.3).
- **A badged SF Symbol variant.** There is no `lock.badge` or `lock.open.badge` symbol in the
  set the app can rely on back to macOS 14, and a custom symbol would mean shipping an asset
  catalogue, which this SwiftPM-only package doesn't have.
- **A coloured dot subview or layer on `NSStatusBarButton`.** Gives an accent-blue dot, but the app
  would have to track appearance, highlight, and tinted menu bars itself, and subviews of the
  status bar button are not a supported customisation point.
- **A non-template image with a palette colour.** Same colour benefit and the same cost: AppKit
  stops adapting the glyph, so it has to be redrawn for every appearance change.

## 4. Testing strategy

### Unit tests (`Tests/UnlatchTests`)

`UpdaterLogicTests.swift`:

- `updaterAvailability`:
  - A `.app` URL with an https feed and a key gives `.enabled`.
  - A non-`.app` URL gives `.notAnAppBundle`, even with both keys set.
  - A missing or empty feed gives `.missingFeedURL`.
  - An `http://` or unparseable feed gives `.insecureFeedURL`.
  - A missing or empty key gives `.missingPublicKey`.
  - When several problems apply, the first in the documented order is reported.
- `allowedUpdateChannels`:
  - `"1.1.0"` and `"0.0.0-abc1234"` give `[]`. So does `nil`.
  - `"1.1.0-beta.1"` and `"1.1.0-beta.2-3-gabc1234-dirty"` give `["beta"]`.
  - `"1.1.0-betamax"` gives `[]`. This guards the `-beta.` delimiter.
- `updateButtonState`: one test per row of the 4-state table, including
  `canCheck == false && updateAvailable == true` giving `.checkDisabled`, and `.disabled(_)` giving
  `.hidden` regardless of the other inputs.

Those three groups merged with T2 (#54). T3 adds, in the same file:

- `updateFooterPresentation(for:)`, one test per state:
  - `.hidden` gives no menu item and no indicator.
  - `.checkDisabled` gives "Check for Updates…", disabled, and no indicator.
  - `.check` gives "Check for Updates…", enabled, and no indicator.
  - `.updateAvailable` gives `UpdateFooterPresentation.updateAvailableTitle`, enabled, and the
    indicator.
- One test that pins the copy: `checkTitle == "Check for Updates…"` and `updateAvailableTitle ==
  "Update Available…"`, both ending in the single-character ellipsis "…" (U+2026), not three dots.
- One composed test: `updateFooterPresentation(for: updateButtonState(availability:
  .disabled(.notAnAppBundle), canCheck: true, updateAvailable: true))` has no menu item and no
  indicator. This is the `swift run` case end to end.

No test for the view itself: the repository has no SwiftUI view tests, and the login item
behaviour behind the menu toggle is already covered by `LoginItemTests.swift`.

T8 adds, in `UpdaterLogicTests.swift`:

- `sparkleShowsScheduledUpdate(inImmediateFocus:)` is `false` for `true` and for `false`. This pins
  the 2026-10-15 decision; changing it must fail a test.
- `updateIndicatorShown(after:current:)`:
  - `.willShowUpdate(handledBySparkle: false, userInitiated: false)` gives `true` from `false`.
  - `.willShowUpdate(handledBySparkle: true, userInitiated: false)` also gives `true` (defensive:
    the indicator doesn't depend on who shows the window).
  - `.willShowUpdate(handledBySparkle: true, userInitiated: true)` keeps `false` as `false` and
    `true` as `true`.
  - `.userAttention` and `.sessionFinished` give `false` from `true` and from `false`.
- One composed test: the event sequence `.willShowUpdate(false, false)`, then `.userAttention`,
  folded from `false`, ends `false`, and after only the first event, `updateButtonState(availability:
  .enabled, canCheck: true, updateAvailable: …)` is `.updateAvailable`.

T9 adds, in `StatusItemLogicTests.swift`:

- `statusItemPresentation(hasLockedWork:updateState:)` for both lock states crossed with
  `.updateAvailable` and `.check`: the symbol name follows `statusSymbolName(hasLockedWork:)`, the
  badge and accessibility value appear only with `.updateAvailable`, and the tool tip is
  "Unlatch" or "Unlatch: update available".
- `.hidden` and `.checkDisabled` give no badge, no value, and "Unlatch".
- One agreement test: for every `UpdateButtonState`, `showsUpdateBadge ==
  updateFooterPresentation(for:).showsUpdateIndicator`. This is the "clears when the popover's
  indicator clears" requirement as a test.
- The copy: `accessibilityLabel == "Unlatch"`, `updateAvailableValue == "Update available"`.

`InfoPlistTemplateTests.swift`:

- Read `Resources/Info.plist.template` via `#filePath`, substitute the two version placeholders, and
  parse it with `PropertyListSerialization`.
- `SUFeedURL` is the https Pages URL.
- `SUPublicEDKey` base64-decodes to exactly 32 bytes.
- `SUAllowsAutomaticUpdates` is `false`.
- `SUScheduledCheckInterval` is the integer `86400` (T8, 2026-10-15).
- `SUEnableInstallerLauncherService`, `SUEnableAutomaticChecks`, and `SUEnableSystemProfiling` are
  all absent. `SUEnableAutomaticChecks` staying absent is what keeps Sparkle's second-launch
  prompt (option A).
- `LSMinimumSystemVersion` is still `14.0`.

Untestable in-process: `AppUpdater` itself, which needs a real bundle, the footer's look,
menu, and VoiceOver output, which T3 checks by hand, and the status item's rendered dot and
VoiceOver output, which T9 checks by hand. No new fixtures are needed,
and `Scripts/generate-fixtures.sh` doesn't change. `UnlatchCoreTests` is untouched.

### Script-level checks (`devops`, local)

- `Scripts/package-app.sh` on today's `main` behaves exactly as before. The binary doesn't link
  Sparkle, so the embed step is skipped.
- `Scripts/package-app.sh` on a scratch branch with Task 2 applied:
  - The §2.8 checks pass locally.
  - `open dist/Unlatch.app` shows the status item.
  - `vmmap $(pgrep -x Unlatch) | grep Sparkle.framework` shows it loaded from
    `Contents/Frameworks`.
- `Scripts/update-appcast.sh` with a throwaway key. Don't use `generate_keys`, which writes to the
  login keychain. `/usr/bin/openssl` is LibreSSL and has no Ed25519, so use Homebrew's OpenSSL 3:
  ```sh
  openssl genpkey -algorithm ed25519 -out k.pem
  export SPARKLE_ED_PRIVATE_KEY="$(openssl pkey -in k.pem -outform DER | tail -c 32 | base64)"
  openssl pkey -in k.pem -pubout -outform DER | tail -c 32 | base64   # SUPublicEDKey for the test bundle
  ```
  Run the four scenarios checked in §2.10:
  - A first stable release with no current feed.
  - A beta release, which adds a channel item.
  - A stable release on the same build as the beta, which must replace the beta item.
    (Superseded by #77: a stable tag no longer shares its beta's build. The scenario still checks
    the defensive drop in `appcast-drop-build.xsl`.)
  - A key mismatch, which must fail.
- `release.yml` via `workflow_dispatch` on the feature branch. `build-and-package` runs every §2.8
  check. `publish`, `appcast`, and `deploy-feed` are skipped.

### Manual: the real N → N+1 upgrade test

This runs on two betas, which needs a maintainer-approved mid-milestone beta (RELEASING.md step 1
exception), on a clean macOS 15+ machine as in RELEASING.md step 3.

1. Tag `v1.1.0-beta.2`. Confirm the release, the `appcast` job, and the `deploy-feed` job are green,
   and that `curl -s https://pablocolaiacovo.github.io/unlatch/appcast.xml` shows a `beta`-channel
   item.
2. On the clean machine:
   - Download the zip in a browser and follow the README's first-launch steps.
   - Save an unlocked PDF to **Desktop** (the destination option, not a picker), and accept any TCC
     prompt.
   - Quit and relaunch. Sparkle's "Check for updates automatically?" prompt appears on this second
     launch. Answer it and note the answer.
   - Note the output of `codesign -dv --verbose=4 /Applications/Unlatch.app 2>&1 | grep CDHash`.
3. Tag `v1.1.0-beta.3` with at least one user-facing PR in between, so the notes aren't empty.
4. In beta.2, open the popover, open the ellipsis menu, and choose "Check for Updates…":
   - The popover closes.
   - Sparkle's window lists 1.1.0-beta.3, with the Markdown notes rendered.
   - "Install and Relaunch" completes, and the footer reads `Version 1.1.0-beta.3 (…)`.
5. Record each of these in a comment on #13. The README task depends on the answers.
   - **Gatekeeper.** Does the relaunched app, or its next manual launch, show a Gatekeeper block?
     Check `xattr -l /Applications/Unlatch.app` for `com.apple.quarantine`.
   - **TCC.** Save to Desktop again. Does the Desktop-folder prompt come back? With an ad-hoc
     signature, the identity is the cdhash, so expect yes. Check `tccutil`-visible entries in
     System Settings > Privacy & Security > Files and Folders.
   - **App Management.** Does macOS show "Unlatch was prevented from modifying apps on your Mac", or
     ask for App Management permission, during install? Ad-hoc code has no team ID, and the macOS
     rule is "same team ID may update". How ad-hoc-to-ad-hoc is treated is the open risk.
   - **The new CDHash.** It must differ from the old one.
6. Scheduled path. Step 4 left the new build installed, so first **reinstall the old build from
   its zip into `/Applications`**, replacing the new one, and follow the README's first-launch steps
   again if Gatekeeper asks. The scheduled path exercises the *installed* build's code, so which
   expectations apply depends on that build. For `v1.1.0-beta.2` → `beta.3` (done, passed), the old
   expectations applied: Sparkle's window appeared behind the frontmost app. From T8 on, the
   installed build must show **no window**. That needs an installed build that contains T8 and an
   older build number than the feed's newest item, see "Manual: the no-window scheduled path"
   below. Automatic checks must be on (the answer from step 2; the setting lives in the
   `com.pablocolaiacovo.unlatch` defaults domain, which survives the reinstall). The `defaults`
   values below also live in that domain, not in the bundle, so they survive the reinstall too, and
   they override the template's `SUScheduledCheckInterval` of 86400 (§2.11). One hour is Sparkle's
   minimum check interval in release builds, so:
   ```sh
   defaults write com.pablocolaiacovo.unlatch SUScheduledCheckInterval -int 3600
   defaults write com.pablocolaiacovo.unlatch SULastCheckTime -date "$(date -u -v-58M '+%Y-%m-%d %H:%M:%S +0000')"
   ```
   - Relaunch Unlatch, switch to another app, and wait about two minutes without opening the
     popover. A pre-T8 build shows Sparkle's window behind the frontmost app. A T8 build shows no
     window; the menu bar icon gets the dot instead (T9).
   - Open the popover. The footer shows "Update Available", the ellipsis has the dot, and the menu
     item reads "Update Available…".
   - Click "Update Available". The popover closes and Sparkle's window comes to the front. Reopen
     the popover: the button and both dots are gone.
   - Repeat with the popover open: rewrite `SULastCheckTime` as above, relaunch, wait a few seconds,
     open the popover, and leave it open for about two minutes. When the check fires, "Update
     Available" and the dots appear in the open popover and on the icon, with no window (T8) or
     with the alert ordered behind (pre-T8).
   - Run `defaults delete com.pablocolaiacovo.unlatch SUScheduledCheckInterval` afterwards.
   - "Remind Me Later" ends Sparkle's session, so the indicator correctly disappears after it too.
7. Channel isolation, after `v1.1.0` ships: a v1.1.0 install isn't offered the next `-beta.N`.

### Manual: the no-window scheduled path (T10, `v1.1.0-beta.4`)

The beta.3 → beta.4 upgrade test (steps 1 to 6 with beta.3 as the old build and beta.4 as the new
one) proves the install path still works after T8 and T9, but its scheduled path runs beta.3's
code, which still lets Sparkle show the window. The new behaviour only runs in a build that
contains T8 *and* finds a newer feed item. Until a `beta.5` exists, use a **rewound copy of
beta.4**: the real beta.4 binary with a lower build number, so the live feed's beta.4 item is
newer than it. The maintainer chose this approach on 2026-10-15 (§6).

```sh
cd "$(mktemp -d)"
gh release download v1.1.0-beta.4 --repo pablocolaiacovo/unlatch --pattern Unlatch.zip
ditto -x -k Unlatch.zip .
PL=Unlatch.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$PL"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.1.0-beta.3' "$PL"   # stays on the beta channel
codesign --force --sign - Unlatch.app          # outer signature only; Sparkle.framework keeps its own
codesign --verify --deep --strict Unlatch.app
osascript -e 'quit app "Unlatch"'              # Quit Unlatch first (or choose Quit in the popover)
rm -rf /Applications/Unlatch.app && ditto Unlatch.app /Applications/Unlatch.app
```

The copy is never quarantined, so Gatekeeper doesn't apply; Gatekeeper, TCC, and App Management
are covered by the real beta.3 → beta.4 run. Then, with the `defaults` from step 6:

1. **Near launch.** Make the check overdue (`SULastCheckTime` two hours back) and launch. No
   Sparkle window appears and Unlatch doesn't become active. The menu bar icon gets the dot within
   a few seconds.
2. **In the background.** Set `SULastCheckTime` 58 minutes back, relaunch, switch to another app,
   and wait about two minutes. No window appears, not even behind other apps (check with Mission
   Control). The icon gets the dot. VoiceOver on the icon reads "Unlatch, Update available".
3. **Popover open.** Repeat 2 with the popover open when the check fires. The footer button, the
   ellipsis dot, and the icon dot appear in place. The popover stays open and key.
4. **Bring it forward.** Click "Update Available" (and in a second run, the "Update Available…"
   menu item). The popover closes, Sparkle's window comes to the front listing 1.1.0-beta.4 with
   its notes, and every indicator clears, the icon dot included.
5. **Remind Me Later.** The window closes and no indicator remains.
6. **Ignore it.** Let a check find the update, don't click, and wait past the next interval: no
   second window and no new check: `defaults read com.pablocolaiacovo.unlatch SULastCheckTime`
   still shows the time of the first check, because Sparkle writes it when a check starts. Quit
   and relaunch: the indicator is gone until the next scheduled check.
7. **Skip This Version.** Bring the update forward and choose Skip. Make the check overdue and
   relaunch: no indicator. "Check for Updates…" still offers beta.4. Then
   `defaults delete com.pablocolaiacovo.unlatch SUSkippedVersion`.
8. **Install.** Bring it forward and choose "Install Update". The app relaunches as the real
   beta.4, with no indicator. The re-signed copy has its own ad-hoc CDHash, so macOS may show an
   App Management or TCC prompt during or after this install. That comes from the rewound copy's
   new identity, not from T8, and is not a regression; the real beta.3 → beta.4 run is the one
   that records those prompts.
9. **Light, dark, and highlight.** With the dot showing, check the icon in a light and a dark menu
   bar, with a tinted wallpaper, and while the popover is open (pressed highlight). The dot stays
   visible and separate from the shackle of both `lock` and `lock.open` (load an encrypted PDF to
   get `lock`).
10. Clean up: `defaults delete com.pablocolaiacovo.unlatch SUScheduledCheckInterval` and
    `defaults delete com.pablocolaiacovo.unlatch SUSkippedVersion` (harmless if step 7 already
    removed it), and reinstall the real beta.4 if step 8 was skipped.

Record the results in the T10 comment on #13.

**Go or no-go.** If step 5 finds that the install *fails* without a manual App Management grant,
stop before tagging v1.1.0 and raise it with the maintainer (Open question 3). Repeated TCC or
Gatekeeper prompts don't block the release. They go into the README.

## 5. Implementation plan

The tasks are ordered as follows. M is the maintainer and T is a task.

```
M1–M2 (keys) ──► T2 ──► T3 ─────────────┐
T1 (devops) ──► T2                       ├─► M5 + T5 (betas, upgrade test) ─► T6 (README)
M3–M4 (secret, Pages) ──► T4 (devops) ───┘                                     T7 (RELEASING, after T4)
```

After the 2026-10-15 decisions:

```
T8 (no window, daily interval) ──► T9 (status item dot) ──► T10 (beta.4, approved as M6, and its upgrade test) ──► T6 (README)
```

T1 must merge before T2. Once T2 lands, the binary links Sparkle, and `main` must stay releasable.
Status on 2026-10-15: T1 merged in #52, T2 merged in #54, T4 merged in #55 (`c5ae4d7`), T3 merged in
#59, and T7 landed in #62 (follow-ups in #64 and #65). T5 is done: `v1.1.0-beta.2` and `v1.1.0-beta.3` are published and
the beta.2 → beta.3 upgrade test passed. T8 to T10 are done (T8 and T9 merged in #67 and #68; the
beta.3 → beta.4 upgrade test passed on 2026-10-15), and T6 is done with the README update. Every PR uses
`Part of #13`, except T6, which uses `Closes #13`. The T3 PR also says `Closes #57`. Each one ends with a clean
`swift build` and a passing `swift test`. Suggested titles follow the changelog convention.
Labels are `project-owner`'s call. The T1, T2, T4, and T7 PRs have no user-facing effect on their
own and probably carry `skip-changelog`. T3, together with #57, is the user-facing line.

### Maintainer steps M1 to M5 (human-only)

M1 to M4 are §2.9 steps 1 to 5. Step 5 there is the github-pages tag rule, so these steps don't
map one-to-one. M5 is approving two mid-milestone betas, `v1.1.0-beta.2` and `v1.1.0-beta.3`, for
the upgrade test. Flag the issue `needs-decision` until M1 to M4 are done.

### T1 (`devops`): Embed and sign Sparkle inside-out when the binary links it

Suggested title: "Embed and sign Sparkle in the app bundle when the app links it".

- `Scripts/package-app.sh`:
  - Add `CODESIGN_ARGS`, `sign()`, and the conditional embed, trim, and inside-out signing from
    §2.3. Rewrite the header comment's #8 note so it points at `CODESIGN_ARGS`.
  - Add `--sequesterRsrc` to the zip.
- `release.yml` `build-and-package`: add the §2.8 checks, each conditional on the binary linking
  Sparkle, so they pass on today's `main`, plus the launch check, which runs unconditionally.

Acceptance criteria:

- On `main`, `Scripts/package-app.sh` produces a bundle with no `Contents/Frameworks`, and the
  existing checks pass.
- With Task 2's `Package.swift` and template changes applied on a local scratch branch (not
  merged), the bundle contains `Contents/Frameworks/Sparkle.framework` without `XPCServices`.
  Every §2.8 check passes, and the app launches and shows the status item.
- A `workflow_dispatch` run of `release.yml` on the branch is green.

### T2 (`macos-developer`): Add the Sparkle dependency and update configuration

Suggested title: "Add Sparkle and the update feed configuration".

This depends on T1 being merged and on the public key from M1.

- `Package.swift`: add the dependency, the product, and `linkerSettings` from §2.2, with the
  comments. Only the `@executable_path/../Frameworks` rpath goes in; do not add `@loader_path`
  (SwiftPM already does, see §2.2 and §2.10). Commit `Package.resolved`.
- `Resources/Info.plist.template`:
  - Add `SUFeedURL`, `SUPublicEDKey` (the literal from M1), and `SUAllowsAutomaticUpdates`
    (`<false/>`), each with a one-line comment.
  - Fix the stale `UnlatchApp.swift's AppDelegate` comment while there.
- `Logic.swift`: add the §2.5 types and functions. Add `UpdaterLogicTests.swift` and
  `InfoPlistTemplateTests.swift`.
- Nothing imports Sparkle yet. Sparkle is linked but unused.

Acceptance criteria:

- `swift build` and `swift test` pass with no new warnings. All new tests pass.
- `swift run Unlatch` launches.
- `Scripts/package-app.sh` produces a bundle that passes T1's checks and launches.
- `UnlatchCore` sources are unchanged: `git diff --stat Sources/UnlatchCore` is empty.

### T3 (`macos-developer`): Check for updates from the popover's ellipsis menu

Suggested title: "Check for updates from a new menu in the popover footer, which now also holds the
version and Open at Login". The title is the changelog line, and users of v1.0 need to know where
the version and Open at Login went, so it names both. Labels: `enhancement` and `area:app`,
without `skip-changelog`: this is the user-facing line for #13 and #57.

This depends on T2 (merged in #54). T4 is merged too (#55, `c5ae4d7`), but the feed only exists
once a Sparkle-enabled tag runs the `appcast` and `deploy-feed` jobs, which first happens with
`v1.1.0-beta.2` under M5. Until then, "Check for Updates…" ends in Sparkle's "update error" alert,
which is expected and not a T3 defect.

**One PR for T3 and #57 (recommended).** The footer of #57 is the only consumer of `AppUpdater`, and
T3's original footer button is exactly what #57 replaces. Two PRs would mean either an `AppUpdater`
with no UI, or shipping and then deleting a footer button that doesn't fit (#57, option A). The
whole change is about 250 lines plus tests and fits one session. The PR body says `Closes #57` and
`Part of #13`. Commit in this order so each step builds and tests green on its own:

1. **Helper and tests.** Add `UpdateFooterPresentation` and `updateFooterPresentation(for:)` to
   `Logic.swift` (§2.5), and the T3 tests from §4 to `Tests/UnlatchTests/UpdaterLogicTests.swift`.
   Leave the T2 helpers as they are.
2. **`AppUpdater` and its wiring.** Add `Sources/Unlatch/AppUpdater.swift` as in §2.4.1. Change
   `AppDelegate` to build and own it, `StatusItemController` to take it and set `onWillPresent`,
   and `PopoverHostingController` and `PopoverView` to take it (§2.4.1, "Lifetime, ownership, and
   isolation"). The footer doesn't read it yet.
3. **The footer.** Replace `PopoverView.footer` with the layout, menu, dot, and accessibility of
   §2.4.2. Remove `loginItemToggle`. Share the hover-capsule style between Quit and "Update
   Available". Update `PopoverView`'s doc comment. Remove `loginItemRevision` from `AppModel` and
   its three observer tests and helper from `LoginItemTests.swift` (§2.4.2).
4. **Docs.** In `README.md`, rewrite "check **Open at Login** at the bottom of the popover" to point
   at the ellipsis menu, and check every other place the README describes the footer. Retake
   `docs/screenshot.png`, which still shows the pre-#51 footer, from a `Scripts/package-app.sh`
   bundle so the new footer is in it. Check `docs/demo.gif`: if it shows the footer, say so in the
   PR, and `project-owner` files a follow-up to re-record it rather than blocking this PR on it.

Must not ship, from `explore/footer-options`: `FooterVariants.swift`, `FooterStyle`, `StubUpdater`,
`FakeLoginItem`, `ExplorationConfig`, any `UNLATCH_FOOTER_*` environment variable, and that branch's
edits to `AppDelegate.swift`, `StatusItemController.swift`, and `PopoverView.swift` (the
`ExplorationConfig` hooks, the forced popover appearance, and the widened `versionText`,
`loginItemToggle`, and `quitButton` access). Copy only the `menuFooter` layout idea, driven by the
real `AppUpdater`.

Acceptance criteria:

- `swift build` is clean with no new warnings under strict concurrency, `swift test` passes, and
  the new tests from §4 pass. No `nonisolated(unsafe)` or `@unchecked Sendable` is added.
  `git diff --stat Sources/UnlatchCore Tests/UnlatchCoreTests` is empty.
- None of the exploration names above appear: `git grep -n -E
  'FooterVariants|FooterStyle|StubUpdater|FakeLoginItem|ExplorationConfig|UNLATCH_FOOTER'` on the
  branch prints nothing.
- Under `swift run Unlatch`:
  - The footer shows only the ellipsis and Quit. No Sparkle alert appears.
  - The menu shows the version, a separator, and Open at Login, disabled. Hovering Open at Login
    shows the "Available when Unlatch runs from an app bundle" tooltip (verified to work on a
    disabled menu item, §2.4.2).
- In a `Scripts/package-app.sh` bundle:
  - The menu shows, in order, `Version <short> (<build>)` (disabled), a separator, "Check for
    Updates…", and Open at Login with a checkmark that matches System Settings > General > Login
    Items.
  - Choosing "Check for Updates…" closes the popover and opens Sparkle's checking window. While that
    window is up, the item is disabled.
  - Open at Login keeps #51's behaviour: checking registers, unchecking unregisters, in
    `.requiresApproval` it opens Login Items, and toggling Unlatch in System Settings is reflected
    the next time the popover opens.
  - In `.requiresApproval` (Unlatch registered, then switched off in System Settings > General >
    Login Items), choosing Open at Login opens Login Items, and when the menu is opened again
    afterwards, Open at Login is still unchecked.
  - Esc with the menu open closes only the menu. A second Esc closes the popover.
  - Quit works by click and by ⌘Q.
- The update-available state, checked with a temporary local edit that is **not committed** (for
  example `updateAvailable = true` in `AppUpdater.init`) until T5 can show it for real:
  - An accent "Update Available" button appears on the left, the ellipsis gets the dot, and the
    menu item reads "Update Available…".
  - Clicking the button or the item closes the popover and calls `checkForUpdates()`.
- Accessibility, checked with VoiceOver and Accessibility Inspector:
  - Normal state: Accessibility Inspector shows the ellipsis with label "More" and no value, and no
    element for the dot.
  - `.updateAvailable`: the ellipsis has label "More" and value "Update available", there is still
    no separate dot element, and the "Update Available" button is its own element labelled "Update
    Available". VoiceOver reads the update once on the ellipsis ("More, Update available, menu
    button") and once on the button, which is the action.
  - Each menu item is read, including Open at Login's checked state.
  - With Keyboard navigation on, Tab reaches "Update Available", the ellipsis, and Quit, and Space
    opens the menu.
- Layout: at 372 pt nothing truncates or clips with the long dev version `0.0.0-abc1234-dirty
  (999)`, in the footer or in the menu, and the footer stays one 26 pt row on every step. This
  replaces the earlier criterion "The footer at 372 pt shows the version, the button, and Quit
  without clipping".
- The PR attaches light and dark screenshots of the normal footer, the update-available footer, and
  the open menu in both states, and the retaken `docs/screenshot.png` is in the diff.
- The maintainer runs the GUI check from #57 by hand on a packaged bundle before merging.
- The update item's wording is "Update Available…" unless the maintainer answers §6 question 5
  otherwise before merge.

### T4 (`devops`): Publish a signed appcast to GitHub Pages from the release workflow

Suggested title: "Publish a signed update feed with every release".

This depends on M3 and M4, and on T2 for the key in the bundle. It can be developed in parallel
with T3, but it must merge before M5's first beta.

- Add `Scripts/update-appcast.sh` and `Scripts/appcast-drop-build.xsl` (§2.6, §2.7).
- Add the `appcast` and `deploy-feed` jobs to `release.yml`, gated on `push`, with the environments,
  permissions, and concurrency from §2.7.
- Update the workflow's header comment and the comment on the `publish` job.

Acceptance criteria:

- The four local scenarios in §4 behave as specified, and the output of each is pasted in the PR.
- The `workflow_dispatch` run is green, and `appcast` and `deploy-feed` are skipped.
- No step ever echoes the secret: `printf '%s' "$SPARKLE_ED_PRIVATE_KEY" |` only, with no
  `set -x` around it.

### T5 (`release-manager` and the maintainer): Cut two betas and run the upgrade test

This depends on T1 to T4 and M5.

- `release-manager` tags `v1.1.0-beta.2` and later `v1.1.0-beta.3`, each only with the
  maintainer's approval of that exact version.
- The maintainer runs §4 "Manual" steps 1 to 6 on a clean machine and posts the findings on #13.

Acceptance criteria: the findings comment exists and covers Gatekeeper, TCC, App Management,
CDHash, and the scheduled path, with the go/no-go outcome stated.

### T6 (`macos-developer`): Document updates in the README (done)

Suggested title: "Explain how Unlatch checks for and installs updates".

This depends on T5's findings, and on T10's, so the README describes the shipped no-window
behaviour.

- Add an "Updates" section:
  - The second-launch prompt.
  - Unlatch checks once a day. When it finds an update it shows no window: the menu bar icon gets
    a dot, and the popover shows "Update Available". Clicking it shows the update and its notes.
  - "Check for Updates…" in the popover's ellipsis menu, and the "Update Available" button.
  - Beta builds follow betas.
  - v1.0.0 users install v1.1.0 manually once.
  - Whatever T5 found about repeated Gatekeeper, TCC, or App Management prompts, and why: ad-hoc
    identity, #8.
- Amend the privacy paragraph. Classifying and unlocking are still fully local. The only network
  traffic is the update check against `pablocolaiacovo.github.io` and the zip download from GitHub,
  and nothing about the user's files is sent. Sparkle's system profiling stays off.
- `Closes #13`.

Acceptance criteria: the README matches the shipped behaviour, and the reviewer has checked it
against T5's comment.

### T7 (`project-owner`): Update RELEASING.md for the update feed

This depends on T4.

- Step 3 (beta smoke test): add the in-app update from the previous beta.
- Step 5 (verify the published release):
  - The `appcast` and `deploy-feed` jobs are green.
  - The feed lists the new item in the right channel.
  - An install of the previous version is offered the update.
- Distribution and signing:
  - The `SPARKLE_ED_PRIVATE_KEY` environment secret.
  - Where the backup lives (not the secret itself).
  - "Losing it strands installs."
  - In the #8 path: `CODESIGN_ARGS` gets `--options runtime --timestamp`, nested code is signed
    inside-out with the same identity, and the §2.8 assertions flip.
- The hotfix path: a deleted release leaves a dead feed item until the hotfix's feed deploys.

### T8 (`macos-developer`): Keep scheduled updates out of sight until the user asks (done)

Suggested title: "Wait for the user before showing a scheduled update". Labels: `enhancement`,
`area:app`. `project-owner` decides on `skip-changelog`; the recommendation is to add it, because
v1.0 users never saw the previous behaviour and T3's line already announces the update UI. PR body:
`Part of #13`.

This depends on T3 (merged in #59). Implements maintainer decisions 1 and 2 of 2026-10-15.

1. `Logic.swift`: add `UpdateReminderEvent`, `sparkleShowsScheduledUpdate(inImmediateFocus:)`, and
   `updateIndicatorShown(after:current:)` (§2.5), with the T8 tests in `UpdaterLogicTests.swift`
   (§4).
2. `AppUpdater.swift`: implement
   `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` returning
   `sparkleShowsScheduledUpdate(inImmediateFocus:)`. Route the three existing delegate methods
   through `updateIndicatorShown(after:current:)`. Keep `supportsGentleScheduledUpdateReminders`
   `true`. Rewrite the doc comment on the gentle-reminder section, which today says Sparkle still
   shows the window, and the one on `updateAvailable` ("A scheduled update was found and the user
   hasn't looked at it yet").
3. `Resources/Info.plist.template`: add `SUScheduledCheckInterval` = `<integer>86400</integer>`
   with a one-line comment ("Scheduled checks once a day; Sparkle's own prompt still asks first").
   Leave `SUEnableAutomaticChecks` absent. Add the T8 assertion to `InfoPlistTemplateTests.swift`.

Acceptance criteria:

- `swift build` is clean with no new warnings under strict concurrency, and `swift test` passes
  with the new tests. No `nonisolated(unsafe)` or `@unchecked Sendable`. `git diff --stat
  Sources/UnlatchCore Tests/UnlatchCoreTests` is empty.
- `AppUpdater`'s delegate methods contain no conditionals of their own; the decisions live in
  `Logic.swift`.
- In a `Scripts/package-app.sh` bundle, `plutil -p dist/Unlatch.app/Contents/Info.plist` shows
  `SUScheduledCheckInterval => 86400`, and "Check for Updates…" still opens Sparkle's checking
  window and reaches the live feed (it reports the beta.3 item or "up to date", depending on the
  local build number).
- The PR says that the change is on RELEASING.md's upgrade-test list (`AppUpdater.swift` and the
  update configuration in the template), so the next beta runs the upgrade test.
- The scheduled path itself can't be shown before a newer feed item exists; T10 covers it. A
  temporary, **uncommitted** local check is enough here: package a bundle with
  `CFBundleVersion` lowered as in §4 "Manual: the no-window scheduled path", run step 1 against the
  live beta.3 item, and paste the result in the PR.

### T9 (`macos-developer`): Show a dot on the menu bar icon when an update is available (done)

Suggested title: "Show a dot on the menu bar icon when an update is available". Labels:
`enhancement`, `area:app`, no `skip-changelog`: it's a visible change. PR body: `Part of #13`.

This depends on T8 (both edit `Logic.swift` and `UpdaterLogicTests.swift`'s neighbourhood; merging
in order avoids conflicts, and the dot is only useful once Sparkle stops showing its window).
Implements maintainer decision 3 of 2026-10-15.

1. `Logic.swift`: add `StatusItemPresentation` and `statusItemPresentation(hasLockedWork:updateState:)`
   (§2.5), with the T9 tests in `StatusItemLogicTests.swift` (§4). `statusSymbolName` stays and is
   used by the new function.
2. `StatusItemController.swift`: replace `observeModel()` and `renderButton(hasLockedWork:)` with
   `observeState()` and `render(_:)`, add `badged(_:)`, and move the tool tip out of
   `configureStatusItem()` (§2.4.3). Update the type's doc comment to mention the update dot.

Acceptance criteria:

- `swift build` is clean with no new warnings under strict concurrency, and `swift test` passes
  with the new tests, including the agreement test between the icon and the footer.
- Under `swift run Unlatch` the icon never shows a dot (the updater is unavailable), and the lock
  glyph still switches between `lock` and `lock.open` as before.
- With a temporary, **uncommitted** `updateAvailable = true` in `AppUpdater.init` on a packaged
  bundle: the icon shows the dot at top-trailing; it doesn't move the glyph; it is legible in light
  and dark menu bars, with a tinted wallpaper, and in the pressed highlight while the popover is
  open; Accessibility Inspector shows the status item with label "Unlatch" and value "Update
  available"; hovering shows "Unlatch: update available". Clicking "Update Available" clears the
  footer indicator and the icon dot together.
- `badged(_:)` is `nonisolated private static` (§2.4.3, Isolation). Running the packaged bundle with
  the dot showing, through a few appearance switches and popover opens, logs no "data race
  detected" or "not called on the main thread" warning in Console for the Unlatch process.
- Accessibility Inspector, without the dot: the `NSStatusBarButton` has no `AXValue` attribute at
  all, not an empty string, after `setAccessibilityValue(nil)`. The footer avoids even an empty value
  for the same reason (`PopoverView.swift`, lines 112-113). If `nil` leaves an empty value, the
  implementer finds another way to clear it and notes it in the PR.
- VoiceOver on the icon reads "Unlatch" once, not twice. The button's accessibility label and the
  image's `accessibilityDescription` are both "Unlatch"; if VoiceOver reads both, drop the image's
  description (pass `nil` to `NSImage(systemSymbolName:accessibilityDescription:)` and in
  `badged(_:)`) and keep the button label.
- The PR attaches 2x screenshots of the icon with and without the dot, light and dark.

### T10 (`release-manager` and the maintainer): `v1.1.0-beta.4` and its upgrade test (done)

This depends on T8 and T9. M6 is done: the maintainer approved `v1.1.0-beta.4` as a
mid-milestone beta on 2026-10-15, to be tagged once T8 and T9 are merged (§6).

- `release-manager` tags `v1.1.0-beta.4` only with the maintainer's approval of that exact
  version, and checks that the `appcast` and `deploy-feed` jobs are green and the live feed has a
  `beta`-channel item for it.
- T8 changes `Sources/Unlatch/AppUpdater.swift` and the update configuration in
  `Resources/Info.plist.template`, both on RELEASING.md's upgrade-test trigger list (step 3), so the
  maintainer re-runs §4 "Manual" steps 2 to 6 from `v1.1.0-beta.3` to `v1.1.0-beta.4` on the clean
  machine, then §4 "Manual: the no-window scheduled path" on a rewound beta.4.

Acceptance criteria: a comment on #13 records the beta.3 → beta.4 install (Gatekeeper, TCC, App
Management, CDHash) and every step of the no-window scheduled path, with a go or no-go for T6 and
the v1.1.0 release.

## 6. Open questions

1. **No in-app "automatically download and install" option (`SUAllowsAutomaticUpdates = false`).**
   This is product scope. Recommendation: keep it off for v1.1. That matches the issue's non-goal
   and the "local and private" positioning. Scheduled *checks* still need the user's consent
   through Sparkle's second-launch prompt.
2. **Approve two mid-milestone betas (`v1.1.0-beta.2`, `v1.1.0-beta.3`) for the upgrade test (M5).**
   RELEASING.md requires the maintainer to approve each exact version. Recommendation: approve
   them. An in-app upgrade can only be tested between two published Sparkle-enabled builds, and
   doing it on betas keeps stable users out of the experiment.
3. **What to do if ad-hoc self-update hits App Management.** This only applies if T5 finds macOS
   blocking the install, as opposed to just prompting. Recommendation: if a one-time grant in
   Privacy & Security > App Management lets it complete, ship v1.1 and document the grant in the
   README. If it fails outright, move #13 out of v1.1 and make #8 (Developer ID) its prerequisite,
   rather than working around a platform protection.
4. **Where the private-key backup lives.** This is the maintainer's call. Recommendation: the
   password manager the maintainer already uses for credentials, as a secure note titled
   "Unlatch Sparkle EdDSA private key (account: unlatch)". Never in the repository, and never in
   iCloud Drive as a plain file.

5. **Wording of the menu item when an update is found (#57). Resolved 2026-10-14: "Update Available…".**
   "Update Available…" or "Install Update…". Recommendation: **"Update Available…"**, because it
   matches the footer's "Update Available" button, so the two controls read as the same action, and
   because clicking it shows Sparkle's alert with release notes and a choice rather than installing
   straight away, which "Install Update…" would suggest. The maintainer confirmed the
   recommendation on 2026-10-14. The string is one constant
   (`UpdateFooterPresentation.updateAvailableTitle`) and one test.

**Resolved by the maintainer on 2026-10-09:** questions 1 to 3 are accepted as recommended.
Automatic install stays off (`SUAllowsAutomaticUpdates = false`), `v1.1.0-beta.2` and
`v1.1.0-beta.3` are approved as mid-milestone betas for the upgrade test (M5). They replace the
originally proposed beta.1 and beta.2, because `v1.1.0-beta.1` was already published on 2026-10-01
as the release-workflow dry run, without Sparkle. The App Management fallback stands: ship with a
documented one-time grant, or make #8 a prerequisite if the install fails outright. Question 4: the private key is backed up in the maintainer's 1Password.

**Decided by the maintainer on 2026-10-15**, after the beta.2 → beta.3 upgrade test passed (the
header of this document has the full text): scheduled checks once a day with
`SUScheduledCheckInterval` = 86400, `SUEnableAutomaticChecks` unset (option A) and
`SUAllowsAutomaticUpdates` `false`; Sparkle never shows a scheduled update by itself, only the
in-app indicator does; and the status item icon shows a dot while an update is available.

**Also decided by the maintainer on 2026-10-15**, answering the three questions those decisions
raised (each as recommended):

- **Colour of the status item dot: a template image in the icon's colour** (black or white, inverted
  when pressed), not accent blue. AppKit keeps it right in light, dark, and tinted menu bars and
  the pressed highlight (§2.4.3, §3.10).
- **Testing the no-window behaviour: a rewound, lower-build copy of beta.4**, after the normal
  beta.3 → beta.4 upgrade test. The scheduled path runs the installed build's code, and beta.3
  still lets Sparkle show its window, so the new behaviour can only be seen in a build that
  contains T8 and finds a newer feed item (§4, "Manual: the no-window scheduled path").
- **`v1.1.0-beta.4` is approved as a mid-milestone beta (M6)**, to be tagged once T8 and T9 are
  merged, so T10 tests both together.

No questions from these decisions remain open.
