# Popover snapshot tests (issue #28)

Issue: #28, "Catch popover layout regressions with snapshot tests" (`enhancement`, `area:app`,
`area:release`, milestone v1.1). Its dependency, #15, is closed.

Since the issue was written, three things have changed, and this design accounts for each:

- Sparkle 2.10.0 is already a dependency and `Package.resolved` is committed (#54). The snapshot
  library is not the package's first dependency, so the issue's scope item about committing
  `Package.resolved` for the first time no longer applies. What remains is checking that the new pins
  land and that CI's cache key changes.
- The popover footer is now the ellipsis menu plus Quit (#57, PR #59). It depends on `AppUpdater`
  (Sparkle) and on `LoginItemService`. §2.3 shows that both can be rendered deterministically with no
  Sparkle side effects, using seams that already exist.
- CI is one job, `build-and-test` in `.github/workflows/ci.yml`. It runs on `xcode-27` with
  `DEVELOPER_DIR` pinned to Xcode 27.0, and branch protection requires it.

## 1. Summary

The tests render every step of `PopoverView` through the production `PopoverHostingController`, at
372 pt and a fixed 2x scale, in light and dark appearance. Each render is compared against a reference
PNG committed under `Tests/UnlatchTests/__Snapshots__/`, using `pointfreeco/swift-snapshot-testing`
1.19.6. Only CI records the references. Every failing `build-and-test` run uploads, as an artifact, the
failed renders with their references and difference images, plus a re-recorded `__Snapshots__` tree
that is ready to commit. A `workflow_dispatch` workflow re-records everything after a toolchain or
runner image change. Locally, the snapshot suite runs only when this Mac's rendering environment
matches the one the references were recorded in. Otherwise it is skipped, so `swift test` stays green.

### Goals

- Six states, each in light and dark (12 images): idle, password, destination, working, done, and
  done with a partial save failure. One optional extra, the footer's "Update Available" state (2
  images), is in T3.
- The rendering path is the one production uses: `PopoverHostingController` with
  `sizingOptions = .preferredContentSize`, and the view sized to the controller's
  `preferredContentSize`.
- Tolerances are tight enough to catch a single changed glyph, so they cannot hide a clipped,
  rewrapped, or truncated line. They were measured during design (§2.6).
- Recording, reading a diff, and re-recording all happen from a CI run. No reference image is ever
  produced on a developer Mac.
- The dependency is linked only by `UnlatchTests`. `UnlatchCore` consumers never fetch it (verified in
  §2.1).

### Non-goals

- The issue's out-of-scope list stands: no XCUITest, no status item glyph, no `NSPopover` chrome, no
  Gatekeeper flow, and no real Finder drag.
- Open menus. The ellipsis menu's contents (version, Check for Updates, Open at Login) are an
  `NSMenu` and are not part of the hosted view. They stay covered by the pure tests in
  `UpdaterLogicTests` and `LoginItemTests`.
- Interaction states: hover, keyboard focus rings, the shake animation mid-flight, and the
  spinner's animation frames.
- Reproducing the exact #15 caption bug. On today's toolchain it no longer reproduces even without the
  `.fixedSize` fix (§2.10). The tests protect the layout as it stands now. Any later change that moves
  pixels fails until someone approves new references.

## 2. Design

### 2.1 Dependency and manifest

`Package.swift`:

```swift
dependencies: [
    // ... Sparkle unchanged ...
    // Test-only: linked by UnlatchTests and nothing else. Exact pin because a library
    // release can change PNG encoding or diffing, which would churn every reference.
    // Bump deliberately, in its own PR, and expect to re-record (RELEASING.md).
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6"),
],
// ...
.testTarget(
    name: "UnlatchTests",
    dependencies: [
        "Unlatch",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ],
    // The reference PNGs and RECORDED_ON.txt are read by path (#filePath), not as
    // bundle resources. Without this, SwiftPM warns "found N file(s) which are unhandled".
    exclude: ["__Snapshots__"]
),
```

1.19.6, released on 2026-09-21, is the latest release. Only the `SnapshotTesting` product is used. Do
not use `InlineSnapshotTesting`, which pulls swift-syntax into the build.

**What the root package resolves** (verified in a scratch copy of this repo): `Package.resolved`
gains four pins, `swift-snapshot-testing` 1.19.6, `swift-custom-dump` 1.7.3,
`swift-issue-reporting` 2.1.2, and `swift-syntax` 604.0.0, next to Sparkle. The library's manifest
declares swift-syntax for its `InlineSnapshotTesting` product. A root package resolves its whole
graph, so swift-syntax is cloned, about 12 MB, but nothing builds it. This applies to every root
build: `swift build`, `swift test`, and `Scripts/package-app.sh` (`swift build -c release --product
Unlatch`) all fetch the four packages, and only `swift test` compiles `SnapshotTesting`. CI caches
`.build`, so after the first run this costs nothing. The release workflow pays for one extra clone
per run, a few seconds.

**What an `UnlatchCore` consumer fetches** (verified): I created a consumer package that depends on a
tagged copy of this repo, with the snapshot dependency added, through a `file://` URL, and uses only
the `UnlatchCore` product. It fetched exactly two packages, the repo itself and **Sparkle**, including
Sparkle's binary artifact zip. It did not fetch swift-snapshot-testing or any of its dependencies.
SwiftPM prunes dependencies that only a dependency package's test targets use, but it still fetches
dependencies of the package's other products, here the `Unlatch` executable. In practice:

- The issue's requirement that "`UnlatchCore` consumers never fetch or build it" holds for the
  snapshot library with no extra work.
- Sparkle already leaks to `UnlatchCore` consumers as a fetch, although they never link it. That is
  outside #28 and changes nothing here. A consumer can avoid it only if `UnlatchCore` moves to its
  own package, or `Unlatch` to its own manifest. Leave it unless a real consumer appears (see §6,
  question 3).

### 2.2 Files

All new code is in the test target. The only production change is the optional T3 seam.

| File | Change |
| --- | --- |
| `Package.swift` | Add the dependency, the product on `UnlatchTests`, and `exclude: ["__Snapshots__"]`. |
| `Package.resolved` | Four new pins. Commit it. |
| `Tests/UnlatchTests/SnapshotSupport.swift` (new) | The gate (mode, environment fingerprint, run decision), the renderer, and `assertPopoverSnapshot`. |
| `Tests/UnlatchTests/SnapshotSupportTests.swift` (new) | Pure tests for the gate and the fingerprint file format. |
| `Tests/UnlatchTests/PopoverSnapshotTests.swift` (new) | The fixtures and the snapshot suite. |
| `Tests/UnlatchTests/__Snapshots__/PopoverSnapshotTests/*.png` (new) | The references, recorded by CI. |
| `Tests/UnlatchTests/__Snapshots__/RECORDED_ON.txt` (new) | The rendering fingerprint of the run that recorded them, written by CI. |
| `Sources/Unlatch/AppUpdater.swift` | T3 only: a `#if DEBUG` factory for the "Update Available" footer state. |
| `.github/workflows/ci.yml` | `devops`, D1: test-step environment variables, the artifact upload on failure, the fingerprint warning, and the cache comment. |
| `.github/workflows/record-snapshots.yml` (new) | `devops`, D2: a `workflow_dispatch` full re-record. |
| `RELEASING.md` | A "Snapshot tests" section (P1). |

The library writes references to `__Snapshots__/<test file name>/<testName>.<name>.png`, next to the
test file. Because `PopoverSnapshotTests.swift` sits at the target root, the references land in
`Tests/UnlatchTests/__Snapshots__/PopoverSnapshotTests/`. That is the location the issue asks for,
and the library's default.

### 2.3 Deterministic state without Sparkle or ServiceManagement

**`AppUpdater`: use the existing seam, no code change.**
`AppUpdater(availability: .disabled(.notAnAppBundle), shortVersion: nil)` is exactly what `swift run`
gets. The `init` returns before it creates `SPUStandardUpdaterController`, so no Sparkle object exists
and nothing can schedule a check or show an alert (`AppUpdater.swift`, the `guard availability ==
.enabled` line). `buttonState` is `.hidden`, so the footer shows the ellipsis button and Quit, which
is the shipping layout for every build without a feed. A test helper wraps it:

```swift
extension AppUpdater {
    /// The `swift run` configuration: no Sparkle object is created.
    @MainActor static func snapshotDisabled() -> AppUpdater {
        AppUpdater(availability: .disabled(.notAnAppBundle), shortVersion: nil)
    }
}
```

**`LoginItemService`: use the existing protocol, no code change.** Every fixture builds
`AppModel(loginItemService: FixedLoginItem(status: .unavailable))`. Never use `AppModel()`: in the
test runner, `Bundle.main` is the test tool, which can have a bundle identifier, and then
`SystemLoginItem` would query `SMAppService` for that tool. The result is irrelevant to the pixels,
because Open at Login lives in the closed menu, but the call is a needless system dependency.
`FixedLoginItem` is a test-only struct like `LoginItemTests`' private `FakeLoginItem`. It is
redeclared in `SnapshotSupport.swift` rather than made shared, to keep `LoginItemTests` untouched.

**The version label needs no seam.** `PopoverView.versionText` reads `Bundle.main`, which in the test
runner is the test tool's bundle. It is drawn only inside the ellipsis menu, which is not open in a
snapshot, so it never reaches the pixels. If the version ever moves back into the footer row, it
needs a seam (for example, injecting the string), because the test tool's Info.plist would otherwise
leak into the references.

**The "Update Available" footer state (T3, optional) needs a small seam.** `updateAvailable` and
`canCheckForUpdates` are `private(set)`, and `.enabled` would create Sparkle's controller. A
debug-only factory reaches the state without touching Sparkle:

```swift
#if DEBUG
extension AppUpdater {
    /// Snapshot tests only. A footer that shows the "Update Available" button, with no
    /// Sparkle object behind it: `checkForUpdates()` does nothing because `controller` is nil.
    /// Compiled out of release builds (`Scripts/package-app.sh` builds `-c release`).
    static func previewingUpdateAvailable() -> AppUpdater
}
#endif
```

Implementation: add a private designated `init(availability:shortVersion:canCheck:updateAvailable:)`
that assigns the three stored properties and never creates a controller. The factory calls it with
`.enabled, nil, true, true`. The public `init` stays byte-for-byte unchanged. Runtime behaviour does
not change, because the code exists only in debug builds and nothing in `Sources/` calls it.

**Sample data**

- Paths come from `FileManager.default.homeDirectoryForCurrentUser`, so `abbreviatedPath` renders
  `~/Documents/...` on any account (`pablo` locally, `runner` in CI). `AppModel.desktopFolder` already
  resolves to `~/Desktop` the same way. No file has to exist, because fixtures set `kind` directly
  instead of calling `classify`.
- `LoadedFile.id` is a random `UUID`, which affects only `ForEach` identity and not pixels.

### 2.4 Fixtures

All of these are in `PopoverSnapshotTests.swift`. Every value is set directly on `AppModel`, whose
`step`, `files`, `password`, `passwordError`, `destination`, `savedURLs`, and `savedTo` are plain
`var`s. Nothing calls `load`, `submitPassword`, or `save`, because those start detached tasks.

```swift
@MainActor
enum PopoverFixture: String, CaseIterable, Sendable {
    case idle, password, destination, working, done, donePartialFailure

    func makeModel() -> AppModel
}
```

| Fixture | State | What it exercises |
| --- | --- | --- |
| `idle` | A fresh model. | The privacy caption on two lines, which is the #15 regression site, and the footer. |
| `password` | Two `.encrypted` files ("Bank statement 2026-09.pdf", "Payslip September.pdf"), `password = "hunter2"`, `passwordError = true`, `step = .password`. | The batch title, the wrapping batch subtitle, the error line, the secure field dots, and two neutral rows. |
| `destination` | One `.encrypted` and one `.owner` file, `destination = .suffix`, `step = .destination`. | Four radio rows with monospaced, middle-truncated hints (`~/Documents/...`, `~/Desktop/...`), and the plural title. |
| `working` | Two files, `step = .working`. | The spinner block. `showsFileRows` is false, so there are no rows. |
| `done` | Two files, both `unlocked = true`. `savedURLs` holds two `-unlocked.pdf` URLs in the same folder. `savedTo` is computed with `doneSummary(destinations:option: .suffix)`. | The success title, the summary path, Show in Finder plus Done, and green rows. |
| `donePartialFailure` | One file `unlocked`, one with `failure = .writeFailed`. `savedURLs` holds one URL, and `savedTo` comes from `doneSummary`. | The mixed title from `doneTitle(savedCount:failedCount:)` and the red failure note row (#5, #21). |

The fixtures use the real helpers (`doneSummary`, and through the view `doneTitle`, `rowInfo`,
`destinationHint`), so a copy change in `Logic.swift` shows up in the references. That is intended.

### 2.5 Rendering

```swift
enum SnapshotAppearance: String, CaseIterable, Sendable {
    case light, dark
    var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
}

/// Renders the production popover content for `model` at a fixed 2x scale on an
/// opaque window-background fill.
@MainActor
func renderPopover(
    _ model: AppModel, updater: AppUpdater, appearance: SnapshotAppearance
) -> NSImage
```

The steps, all verified in a scratch copy of the repo (§2.10):

1. `let controller = PopoverHostingController(model: model, updater: updater)` is the exact production
   type, including `sizingOptions = .preferredContentSize`.
2. `controller.view.appearance = NSAppearance(named: appearance.name)`. This overrides the system
   appearance: the maintainer's Mac runs in system Dark mode, and the light render still came out
   light.
3. `layoutSubtreeIfNeeded()`, then `size = controller.preferredContentSize`, then
   `view.setFrameSize(size)` and `layoutSubtreeIfNeeded()` again. The height is whatever production
   would hand `NSPopover`, so a step that grows, shrinks, or clips changes the image size, and that
   alone fails the comparison.
4. Draw into an explicitly sized `NSBitmapImageRep`, with `pixelsWide = width * 2`, `pixelsHigh =
   height * 2`, and `rep.size = size`, using `view.cacheDisplay(in: view.bounds, to: rep)`. Do **not**
   use the library's `Snapshotting<NSView, NSImage>.image`. That strategy sizes the bitmap from the
   view's or screen's backing scale, which is 2.0 on the maintainer's Mac and undocumented on GitHub's
   virtualised runners. A 1x runner would produce half-size images that never match. With an explicit
   rep, the pixel dimensions are fixed regardless of the display.
5. Composite onto an opaque fill. The popover's background comes from `NSPopover`'s chrome, which is
   out of scope, so the hosted view is transparent and dark mode would be white text on alpha. Create
   a second rep of the same size, fill it with `NSColor.windowBackgroundColor` inside
   `NSAppearance(named:).performAsCurrentDrawingAppearance`, and draw the first rep over it. This
   stands in for the popover material. It is a test-only choice and changes nothing at runtime.
6. Return `NSImage(size: size)` with the composited rep. The renders are compared with
   `Snapshotting<NSImage, NSImage>.image(precision:perceptualPrecision:)`, whose snapshot step is
   synchronous.

The idle render is 744 x 566 px, and the done render with two rows is 744 x 504 px. One reference is
roughly 40 to 80 KB, so 14 references come to about 1 MB in git. They don't need LFS.

### 2.6 Tolerances: `precision: 0.9999`, `perceptualPrecision: 0.98`

These were measured against the real idle step at 744 x 566 px, about 421,000 pixels:

| Change to the idle caption | 0.99 | 0.9998 | 0.9999 | 1.0 |
| --- | --- | --- | --- | --- |
| None, two consecutive renders | pass | pass | pass | pass (bit-identical) |
| One glyph changed (`Mac.` to `Mac!`) | pass | **pass** | fail | fail |
| One word changed, line rewrapped (`one.` to `it.`) | **pass** | fail | fail | fail |

All rows use `perceptualPrecision: 0.98`.

- `perceptualPrecision: 0.98` means a pixel counts as matching when its CIE Lab ΔE against the
  reference is at most 2 (`deltaThreshold = (1 - p) * 100` in the library's `perceptuallyCompare`).
  ΔE 2 is about the threshold of a difference visible on close inspection. It absorbs antialiasing
  and compositing noise, for example a GPU path on one machine and the library's CPU fallback on
  another, without ignoring a real colour change. Text strokes moving or vanishing produce ΔE of 20
  to 80, so they always count.
- `precision: 0.9999` allows at most 0.01% of pixels beyond that ΔE, about 42 pixels on the idle
  image, which is less than one 11 pt glyph at 2x. As the table shows, 0.9998 already misses a
  one-glyph change and 0.99 misses a rewrapped line, so those are too loose. Clipping and truncation
  are caught regardless: a lost line changes the image height, which fails before any pixel is
  compared, and middle truncation shifts a whole run of monospaced glyphs.
- Not `1.0`: on identical hardware and software the renders are bit-identical, so `1.0` would pass in
  CI today. But a CPU fallback for Core Image, or a different GPU on a re-imaged runner, can move a
  handful of edge pixels, and that would turn the required check red for no visible reason.
- Escape hatch: if CI ever flakes on these values, check whether the failure is real by downloading
  the difference image. Then loosen `precision` to 0.9998 (never below) in one place,
  `SnapshotTolerance` in `SnapshotSupport.swift`, and record the reason there. Do not loosen
  `perceptualPrecision`.

```swift
enum SnapshotTolerance {
    static let precision: Float = 0.9999
    static let perceptualPrecision: Float = 0.98
}
```

### 2.7 Record modes and the local gate

Two environment variables control behaviour. One is the library's own, and the other belongs to this
design.

**`SNAPSHOT_TESTING_RECORD`** (library: `all`, `failed`, `missing`, `never`). The library defaults to
`missing`, which would silently write references on a developer Mac. `assertPopoverSnapshot` passes
`record:` explicitly. It uses the environment variable's value when set, and `.never` otherwise:

```swift
static func recordMode(environment: [String: String]) -> SnapshotTestingConfiguration.Record {
    environment["SNAPSHOT_TESTING_RECORD"].flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
        ?? .never
}
```

So nothing is written into the source tree unless someone asks for it. CI asks with `failed` in
`build-and-test` and with `all` in the record workflow. Under `failed`, a mismatch or a missing
reference overwrites or creates the reference in the runner's workspace **and still fails the test**,
so the required check stays red until someone commits the images (verified in §2.10).

**`UNLATCH_SNAPSHOTS`** (this design: `auto`, `require`, `skip`; it defaults to `auto` when unset or
unrecognised):

```swift
enum SnapshotMode: Equatable, Sendable {
    case auto, require, skip
    init(environment: [String: String])
}

/// What affects pixels on a given Mac besides the code: the OS build, and the system-wide
/// settings that change control colours or contrast.
struct RenderEnvironment: Equatable, Sendable {
    var osVersion: String          // "27.0.1 (26A434)": operatingSystemVersion + sysctl kern.osversion
    var accentColor: String        // AppleAccentColor in the global domain, "default" when absent
    var highlightColor: String     // AppleHighlightColor, "default" when absent
    var increaseContrast: Bool     // NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    var reduceTransparency: Bool   // NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    @MainActor static func current() -> RenderEnvironment
    init?(fileContents: String)    // key=value lines; nil on a missing key
    var fileContents: String
}

enum SnapshotRunDecision: Equatable, Sendable {
    case run
    case skip(reason: String)
}

func snapshotRunDecision(
    mode: SnapshotMode, recorded: RenderEnvironment?, current: RenderEnvironment
) -> SnapshotRunDecision
```

| Mode | Decision |
| --- | --- |
| `require` (CI) | Always `.run`. |
| `skip` | Always `.skip`. |
| `auto` (local default) | `.run` when `RECORDED_ON.txt` exists and parses, and equals `current`. Otherwise `.skip`, with a reason that names the first field that differs, for example "references were recorded on macOS 27.0.1 (26A434); this Mac runs 27.1 (26B12). Set UNLATCH_SNAPSHOTS=require to run anyway". |

The suite carries the gate as a Swift Testing condition trait, so a skip shows up in `swift test`
output as a skipped suite, not as silence:

```swift
@MainActor
@Suite(.enabled("Snapshot references were recorded in a different rendering environment; see RELEASING.md") {
    await SnapshotGate.shouldRun()   // prints the detailed skip reason to stderr when false
})
struct PopoverSnapshotTests { ... }
```

`SnapshotGate.shouldRun()` hops to the main actor for `RenderEnvironment.current()`, because the
`NSWorkspace` accessibility properties are main-actor reads, and reads `RECORDED_ON.txt` through a
path built from `#filePath`.

**`RECORDED_ON.txt` is written by the tests, not by a shell step,** so its format always matches
`RenderEnvironment.current()`. Shell output from `sw_vers` prints "27.0", whereas
`operatingSystemVersion` gives "27.0.0", and the two drift. `assertPopoverSnapshot` writes it once
per process when the record mode is `all` or `failed` and the mode is `require`, which happens only in
CI. Content that hasn't changed produces no git diff.

**Why gate locally rather than always run or always skip**

- Always running breaks the requirement that `swift test` stays green for the maintainer. Rendering
  lives in the OS frameworks (SwiftUI, AppKit, Core Text). The first macOS point update on the
  maintainer's Mac that is ahead of or behind the runner image could fail all 12 tests, and so could a
  non-default accent colour. The issue itself says local diffs are expected.
- Always skipping unless opted in means the suite never runs locally, even on a Mac identical to CI.
  The issue explicitly wants the tests to run in `swift test` locally.
- The gate runs the suite exactly when a local result means something. Today the maintainer's Mac
  (macOS 27.0.1, Xcode 27.0, default accent) may well match the runner. When it doesn't, the skip is
  visible and says why. The fingerprint does not include the Xcode version, because there is no
  public runtime API for the SDK a test binary linked against. CI pins Xcode through `DEVELOPER_DIR`,
  and changing that pin is a documented re-record trigger (§2.8). If a local Xcode differs from CI's
  while the OS matches and that changes pixels, `UNLATCH_SNAPSHOTS=skip swift test` is the documented
  escape.

### 2.8 CI flows

**A. Every PR and push: `build-and-test` (D1).** The test step gets:

```yaml
      - name: Test
        env:
          UNLATCH_SNAPSHOTS: require
          SNAPSHOT_TESTING_RECORD: failed
          SNAPSHOT_ARTIFACTS: ${{ runner.temp }}/snapshots/failures
        run: swift test
```

On failure, a step assembles and uploads one artifact:

```
popover-snapshots-<run_attempt>/
  failures/PopoverSnapshotTests/
    popover.idle-light.png              the new render (written by the library)
    popover.idle-light.reference.png    the committed reference (written by the helper)
    popover.idle-light.difference.png   a difference blend (written by the helper)
  recorded/                             the runner's Tests/UnlatchTests/__Snapshots__ after the run:
    RECORDED_ON.txt                     every reference that failed or was missing has been
    PopoverSnapshotTests/*.png          re-recorded; the rest are unchanged
```

- `failures/` comes from the library: `SNAPSHOT_ARTIFACTS/<file name>/<test>.<name>.png` holds the
  failing render. The library's reference, failure, and difference attachments are emitted only when
  Xcode runs the tests (`__XCODE_BUILT_PRODUCTS_DIR_PATHS`), never under `swift test`. So
  `assertPopoverSnapshot` adds them itself. It reads the reference bytes **before** calling
  `verifySnapshot`, because `failed` mode overwrites the reference. When `verifySnapshot` returns a
  message, it writes `<name>.reference.png` and a `CIDifferenceBlendMode` `<name>.difference.png`
  next to the library's file, then calls `Issue.record` with the message at the caller's source
  location.
- `recorded/` is a copy (`cp -R`) of the workspace's `Tests/UnlatchTests/__Snapshots__`. Upload one
  directory under `runner.temp`. Passing a workspace path and a temp path to `upload-artifact`
  together would produce a common-ancestor layout rooted at `/`.
- The upload step runs `if: failure()` with `if-no-files-found: ignore`, because a compile failure
  produces no snapshots. Use `retention-days: 14` and `actions/upload-artifact@v7`, the version
  `release.yml` already uses. The artifact name includes `github.run_attempt`, the same lesson as the
  Pages artifact in `release.yml`: a re-run must not collide with the first attempt's artifact.
- On success, a step warns when the runner's fingerprint differs from the committed one:
  `git status --porcelain -- Tests/UnlatchTests/__Snapshots__/RECORDED_ON.txt` is non-empty, so it
  emits `echo "::warning title=Snapshot environment changed::..."`. This happens when GitHub updated
  the image's macOS and the pixels still passed within tolerance. It is a nudge to run flow C, not a
  failure, because the image updates under us and must not block unrelated PRs while the references
  still match.
- Update the stale cache comment, which still says no `Package.resolved` is committed. The key
  already hashes `**/Package.resolved`, so adding the dependency changes the key on the first run.
  Confirm that in the PR by comparing the "Cache .build" step's key against a previous `main` run.

**B. Recording new or changed references from a PR (no special job).** Use this flow for the first
recording in T2, for a new fixture, or for an intentional layout change:

1. Push. `build-and-test` fails, either with "No reference was found on disk" or with "does not
   match reference. A new snapshot was automatically recorded."
2. Run `gh run download <run-id> -n popover-snapshots-<attempt> -D /tmp/snapshots`.
3. Read the diff. Open `failures/PopoverSnapshotTests/` in Finder and use Quick Look, selecting a
   render, its `.reference.png`, and its `.difference.png` together. In the difference image, black
   means identical, and lit pixels show what moved.
4. If the change is intended, run `rsync -a --delete /tmp/snapshots/recorded/
   Tests/UnlatchTests/__Snapshots__/` and commit the result. `--delete` drops references of removed
   fixtures, which the library never deletes itself. Push. The next run passes, because CI compares
   against images CI recorded.
5. If the change is not intended, fix the code. Do not commit the images.

**C. Full re-record after a toolchain or image change: `record-snapshots.yml` (D2).** Use this when
`DEVELOPER_DIR` or `runs-on` in `ci.yml` changes, when the snapshot library is bumped, or when flow
A's environment warning appears. Flow B would re-record only the failing references, leaving the rest
recorded on the old image within tolerance. A full re-baseline keeps the whole set from one
environment.

```yaml
name: Record snapshots
on:
  workflow_dispatch:      # run on the branch of the PR that will carry the new references
permissions:
  contents: read          # it never pushes; a human commits the artifact
env:
  DEVELOPER_DIR: ...      # must equal ci.yml's pin (comment cross-references both files)
jobs:
  record:
    runs-on: xcode-27     # must equal ci.yml's runs-on
    steps:
      - checkout, swift --version, cache (same key scheme as ci.yml)
      - name: Record all references
        run: swift test --filter PopoverSnapshotTests || true    # record mode reports every assertion as an issue
        env: { UNLATCH_SNAPSHOTS: require, SNAPSHOT_TESTING_RECORD: all }
      - name: Verify the new references on the same runner
        run: swift test --filter PopoverSnapshotTests
        env: { UNLATCH_SNAPSHOTS: require, SNAPSHOT_TESTING_RECORD: never }
      - name: Upload
        if: always()
        uses: actions/upload-artifact@v7    # name: recorded-snapshots-<run_attempt>, path: Tests/UnlatchTests/__Snapshots__
```

The verification step shows that the references reproduce on a second run within the same job, so
they are not flaky before anyone commits them. `|| true` on the record step is deliberate, because
record mode always reports issues. The verification step is what decides the job's colour.
`workflow_dispatch` only works once the file is on `main`. That is why bootstrapping (T2) uses flow
B, and D2 lands after T2.

The workflow never commits or pushes. Pushing from CI would bypass review and would need
`contents: write`. The images are reviewed in the PR like any other change.

### 2.9 Concurrency

- `PopoverSnapshotTests` is a `@MainActor` suite. `AppModel`, `AppUpdater`, `PopoverHostingController`,
  `NSView` drawing, and `NSAppearance` are all main-actor. Swift Testing still runs other suites in
  parallel off the main actor, which is unaffected.
- `assertSnapshot` and `verifySnapshot` are synchronous, non-isolated functions that block on
  `XCTWaiter`. With the `NSImage` strategy, the snapshot callback fires synchronously, so the wait
  returns immediately and never needs the main run loop to make progress.
- The library compiles in Swift 5 language mode. Importing it into the Swift 6 test target produced
  no concurrency diagnostics in the scratch build.
- Only `Sendable` values cross isolation: `SnapshotMode`, `RenderEnvironment`, and
  `SnapshotRunDecision` are value types. The trait's condition closure is `@Sendable async` and hops to
  the main actor explicitly.
- File names: pass `testName: "popover"` explicitly. A parameterized test's `#function` is
  `popover(_:)`, which the library sanitizes to `popover-_`. Names are `<fixture>-<appearance>`, for
  example `popover.idle-light.png`. Every assertion is named, so the library's per-test counter is
  never used, and ordering cannot change file names.

### 2.10 Verified during design (macOS 27.0.1 26A434, Xcode 27.0, Swift 6.4, this Mac)

All in scratch packages under `/tmp`, never in the repo:

- swift-snapshot-testing 1.19.6, source read directly. I confirmed `assertSnapshot(of:as:named:record:...)`,
  `verifySnapshot` returning `String?`, the `.snapshots(record:diffTool:)` Swift Testing trait,
  `withSnapshotTesting(record:diffTool:operation:)`, `SNAPSHOT_TESTING_RECORD` read once at startup
  with the default `missing`, `SNAPSHOT_ARTIFACTS` falling back to `NSTemporaryDirectory()`, and
  attachments being Xcode-only. The library's SwiftUI view strategy is iOS and tvOS only. On macOS
  the options are `NSView`, `NSViewController`, and `NSImage`.
- The real `PopoverView`, through `PopoverHostingController`, renders headless under `swift test`
  with the disabled `AppUpdater` and a fake login item. The footer shows the ellipsis and Quit, with
  no Sparkle object. The idle render is 372 x 283 pt, and two renders are bit-identical. The spinner
  in a static frame renders identically between runs.
- The idle caption renders on two lines both with and without its `.fixedSize` modifier. That holds
  when detached, inside an offscreen window, and inside a real `NSPopover` shown from a test, where
  `contentSize` is 372 x 283 both ways. The #15 bug does not reproduce on this toolchain, so the tests
  guard the current layout rather than that specific historical failure (§1, non-goals).
- The tolerance table in §2.6.
- `failed` mode with `SNAPSHOT_ARTIFACTS` writes the failing render into the artifacts directory,
  overwrites the workspace reference, and fails the test.
- The consumer fetch results in §2.1, and the `__Snapshots__` "unhandled files" warning without
  `exclude`.

**Not verifiable from here, so it is the first thing D1 and T2 check in CI.** First, headless
rendering on the `xcode-27` runner. GitHub's macOS runners run a logged-in GUI session, so it is
expected to work. Second, that the runner's renders are stable across re-runs at these tolerances.

### 2.11 Edge cases

| Case | Behaviour |
| --- | --- |
| New fixture with no reference | Locally (`auto`, `.never`), the test fails with "No reference was found on disk. New snapshot was not recorded because recording is disabled", if the gate runs at all. In CI, flow B records it. A suite with references missing for a new fixture is a transient state while a PR is open. |
| `RECORDED_ON.txt` missing or unparsable | `auto` skips with that reason. `require` runs, and the next CI recording writes the file. |
| A runner image patch update that changes pixels | `build-and-test` fails on every PR until someone runs flow C and merges the result. See §6, question 1. |
| A runner image update that doesn't change pixels | Green, with the "Snapshot environment changed" warning. Run flow C when convenient, so local `auto` matches again. |
| Non-default accent or highlight colour, or Increase Contrast, on a dev Mac | The fingerprint differs, and `auto` skips with that reason. |
| A developer records locally with `SNAPSHOT_TESTING_RECORD=all` | The images are written into the tree. Review catches them: the PR's `RECORDED_ON.txt` would show the local fingerprint, and the next CI run would fail or warn. The RELEASING.md section says not to commit local recordings. |
| Text that depends on locale | All copy is hard-coded English, and nothing formats numbers or dates with a locale. No seam is needed. |
| Localisation or system font changes in a macOS update | They are covered by the image-change cases above. |

## 3. Trade-offs

### 3.1 Recording in CI: a `failed`-mode required job plus a dispatch workflow, or a dispatch workflow only

A dispatch-only design keeps `build-and-test` on `never` and requires a manual dispatch for every
layout change. It adds a step to every UI PR, and it cannot bootstrap, because the workflow must be on
`main` first. Running `failed` mode in the required job makes every failing run carry the fix, at no
cost when tests pass. The library's own guidance, `never` on CI, guards against test retries passing
on freshly recorded images. Swift Testing here has no retries, and `failed` still fails the run, so
that risk does not apply. The dispatch workflow remains for full re-baselines, where `failed` would
leave old-environment images in place.

### 3.2 Local behaviour: fingerprint gate, always run, or opt in

See §2.7. The gate costs about 60 lines of test support and one text file. In return, the suite runs
locally whenever the result is meaningful, and `swift test` never goes red because of the
environment.

### 3.3 Fixed 2x bitmap, or the library's `NSView` strategy

The library's strategy follows the screen's backing scale, so on a 1x runner every reference would
come out half-size. A fixed rep costs about 20 lines and removes the dependency on the display
entirely. Rendering at 1x would halve repo size, but it would blur 11 pt text into fewer pixels and
weaken the one-glyph sensitivity measured in §2.6.

### 3.4 Production hosting controller, or a bare `NSHostingView(rootView: PopoverView(...))`

The production controller exercises `sizingOptions = .preferredContentSize`, the sizing path #15 was
about, at the cost of nothing. A bare hosting view would measure `fittingSize`, which can diverge from
what `NSPopover` receives.

### 3.5 Hosting in a real `NSPopover`

Tried during design. It works on this Mac but adds a window and a popover with real screen placement,
asynchronous showing, and arrow chrome, which the issue puts out of scope. It produced the same size
as the detached controller, so it buys nothing today.

### 3.6 Pinning: `exact` or `.upToNextMinor`

Exact. A patch release can change PNG encoding or diffing, and when it does, every reference churns
in an unrelated PR. That matches the Sparkle pin's convention.

### 3.7 Alternatives to swift-snapshot-testing

There is no Apple first-party image snapshot API for SwiftPM tests. Hand-rolling the comparison is
about 150 lines and would lose the maintained perceptual comparison and its CPU fallback. The
library's swift-syntax pull is fetch-only (§2.1).

## 4. Testing strategy

**Unit tests (`Tests/UnlatchTests/SnapshotSupportTests.swift`, plain Swift Testing, always run)**

- `SnapshotMode(environment:)`: unset gives `auto`, `require` and `skip` parse, and garbage gives
  `auto`.
- `recordMode(environment:)`: unset gives `.never`, `failed` gives `.failed`, and garbage gives
  `.never`.
- `snapshotRunDecision`: `require` runs even when the fingerprint is nil or different. `skip` always
  skips. `auto` runs when the fingerprint is equal, skips when nil, and skips when each single field
  differs, with that field named in the reason.
- `RenderEnvironment`: `init?(fileContents:)` and `fileContents` round-trip. A missing key returns
  nil. Unknown extra keys are ignored, so the format can grow.
- These are pure. They never call `RenderEnvironment.current()` and touch no file.

**Snapshot tests (`Tests/UnlatchTests/PopoverSnapshotTests.swift`, gated)**

- `@Test(arguments: PopoverFixture.allCases) func popover(_ fixture:)` runs
  `assertPopoverSnapshot(fixture.makeModel(), named: fixture.rawValue)` in both appearances, giving
  12 references.
- T3: `@Test func footerUpdateAvailable()` renders the idle fixture with
  `AppUpdater.previewingUpdateAvailable()`, giving 2 references.

**Fixtures**: none under `Tests/UnlatchCoreTests/Fixtures`, and `Scripts/generate-fixtures.sh` does
not change. The references are CI-generated test data, not PDF fixtures.

**Manual or CI-only checks**

- T2's PR: the first run fails with 12 "No reference" issues and uploads `recorded/`. After the images
  are committed, the run is green. Then use "Re-run all jobs" twice and confirm both are green, which
  is the flake check for §2.6's values.
- Sabotage check on the T2 branch, not committed: delete `.fixedSize(horizontal: false, vertical:
  true)` and change a word of the idle caption, and confirm that CI fails, that the artifact's
  difference image shows the moved text, and that `recorded/` contains a replacement. Revert.
- D2: one dispatch run on a branch is green and uploads 12 to 14 PNGs plus `RECORDED_ON.txt`
  identical in size to the committed set.
- Locally: `swift test` is green on the maintainer's Mac. The output shows the suite either run or
  skipped with a reason. `UNLATCH_SNAPSHOTS=skip swift test` skips it.
  `UNLATCH_SNAPSHOTS=require swift test` runs it, and on a matching Mac it passes.

## 5. Implementation plan

```
D1 (devops, ci.yml) ──► T1 (infra) ──► T2 (snapshots + CI-recorded references) ──► D2 (record workflow) ──► P1 (RELEASING.md, Closes #28)
                                         └──► T3 (optional, update-available footer)
```

D1 goes first, so that the very first CI run of T2 already uploads the artifact needed for
bootstrapping. Its changes do nothing until snapshot tests exist: the environment variables are
unused, the upload step is failure-only with `ignore`, and the warning step finds no file. T1 and D1
can be worked on in parallel, but merge D1 first. Each PR uses `Part of #28`, except the last one to
merge, which uses `Closes #28`. None of them has a user-facing effect, so every PR carries
`skip-changelog` plus `area:app` (T*) or `area:release` (D*, P1). Labels are `project-owner`'s call.

### D1 (`devops`): Upload snapshot failures and re-recorded references from CI

Suggested title: "Upload failed and re-recorded popover snapshots from CI runs".

- `ci.yml`, "Test" step: add `UNLATCH_SNAPSHOTS: require`, `SNAPSHOT_TESTING_RECORD: failed`, and
  `SNAPSHOT_ARTIFACTS: ${{ runner.temp }}/snapshots/failures` (§2.8 A).
- Add "Collect snapshots" (`if: failure()`), which runs `mkdir -p` on the artifact root and then, if
  `Tests/UnlatchTests/__Snapshots__` exists, copies it to `${{ runner.temp }}/snapshots/recorded`.
  Add "Upload snapshots" (`if: failure()`, `upload-artifact@v7`, name
  `popover-snapshots-${{ github.run_attempt }}`, `if-no-files-found: ignore`, `retention-days: 14`).
- Add the success-only fingerprint warning step (§2.8 A).
- Rewrite the cache step's comment: `Package.resolved` is committed, and Sparkle plus the test-only
  snapshot packages are pinned there.
- Next to `DEVELOPER_DIR`, add one comment line saying that changing it or `runs-on` requires a full
  snapshot re-record (RELEASING.md, "Snapshot tests").

Acceptance criteria:

- `build-and-test` is green on the PR, which has no snapshot tests yet. A failing run on a scratch
  branch, for example with a deliberately broken test that is not merged, shows the collect and upload
  steps running, with no error when no snapshot files exist.
- `actionlint` (or the GitHub workflow editor) reports no errors.
- The job name stays `build-and-test`, so branch protection is unaffected.

### T1 (`macos-developer`): Add the snapshot-testing dependency and the test support

Suggested title: "Add snapshot test support for the popover".

- `Package.swift` and `Package.resolved` as in §2.1, with the comments.
- `Tests/UnlatchTests/SnapshotSupport.swift`: `SnapshotMode`, `RenderEnvironment` (including
  `current()`, reading `kern.osversion` with `sysctlbyname`), `SnapshotRunDecision`,
  `snapshotRunDecision`, `recordMode(environment:)`, `SnapshotGate.shouldRun()`, `SnapshotTolerance`,
  `SnapshotAppearance`, `FixedLoginItem`, `AppUpdater.snapshotDisabled()`, `renderPopover` (§2.5), and
  `assertPopoverSnapshot(_:updater:named:filePath:line:column:)`. The last one renders both
  appearances, reads each reference first, calls `verifySnapshot` with `testName: "popover"` and the
  explicit record mode, writes `.reference.png` and `.difference.png` into the artifacts directory on
  failure, records the issue, and writes `RECORDED_ON.txt` in CI record modes (§2.7, §2.8).
- `Tests/UnlatchTests/SnapshotSupportTests.swift`: the unit tests in §4.
- No snapshot test and no reference image yet.

Acceptance criteria:

- `swift build` and `swift test` pass locally with no new warnings, including no "unhandled files"
  warning. `git diff --stat Sources/` is empty.
- `Package.resolved` lists exactly the four new pins plus Sparkle, and `SnapshotTesting` appears only
  in the `UnlatchTests` dependencies.
- CI is green, and the cache key differs from the last `main` run's (state both keys in the PR).

### T2 (`macos-developer`): Snapshot every popover step in light and dark

Suggested title: "Catch popover layout regressions with snapshot tests".

Depends on D1 and T1 being merged.

- `Tests/UnlatchTests/PopoverSnapshotTests.swift`: `PopoverFixture` (§2.4), and the gated
  `@MainActor` suite with the parameterized `popover(_:)` test.
- Bootstrap the references through flow B (§2.8): push, download `popover-snapshots-1`, rsync
  `recorded/` into `Tests/UnlatchTests/__Snapshots__/`, inspect each of the 12 PNGs by eye, which is
  the human approval of the baseline, commit, and push.
- Run the flake check and the sabotage check from §4, and paste the results into the PR. The PR body
  states the tolerance values and links §2.6, as the issue asks.

Acceptance criteria:

- `__Snapshots__/PopoverSnapshotTests/` holds exactly 12 PNGs, and `RECORDED_ON.txt` shows the
  runner's fingerprint. Every image came from the CI artifact.
- `build-and-test` is green, and two "Re-run all jobs" runs are green.
- Local `swift test` is green, and the output shows the suite either passing or skipped with a reason.
- `git diff --stat Sources/` is empty.

### T3 (`macos-developer`, optional): Snapshot the "Update Available" footer

Suggested title: "Snapshot the popover footer while an update is available".

- `AppUpdater.swift`: the private designated init and the `#if DEBUG`
  `previewingUpdateAvailable()` factory (§2.3). The public `init` stays unchanged.
- `PopoverSnapshotTests.swift`: `footerUpdateAvailable()`, then record its 2 references with flow B.

Acceptance criteria:

- `swift build -c release --product Unlatch` succeeds, and the factory is absent from release builds.
  Check with `nm` on the release binary, or by confirming it compiles only under `DEBUG`.
- `UpdaterLogicTests` is unchanged and passing. CI is green with 14 references.

### D2 (`devops`): Re-record all snapshots on demand

Suggested title: "Add a workflow that re-records the popover snapshots on CI's toolchain".

Depends on T2 being merged, because the dispatch needs the tests and the file on `main`.

- `.github/workflows/record-snapshots.yml` as in §2.8 C. Its comments cross-reference `ci.yml`'s
  `DEVELOPER_DIR` and `runs-on` as values that must stay identical. Add the reverse reference in
  `ci.yml`.

Acceptance criteria:

- A dispatch on a branch is green, the verification step passes, and the artifact holds all
  references plus `RECORDED_ON.txt`. Rsyncing it over the tree on that branch produces no diff, or
  only a `RECORDED_ON.txt` diff.
- `permissions: contents: read`, and nothing pushes.

### P1 (`project-owner`): Document snapshot tests in RELEASING.md

Suggested title: "Explain how to record and read popover snapshots".

CLAUDE.md gives `project-owner` ownership of `RELEASING.md`. The issue and the brief suggested
`macos-developer`. If the maintainer prefers, `macos-developer` can draft the section in the T2 PR and
`project-owner` can review it.

- Add a "Snapshot tests" section (or a short `Design/`-independent page that it links to) covering:
  - CI's references are authoritative.
  - The `UNLATCH_SNAPSHOTS` and `SNAPSHOT_TESTING_RECORD` meanings.
  - Flow B step by step, with the `gh run download` and `rsync` commands.
  - How to read `failures/`: render, `.reference.png`, and `.difference.png`.
  - Flow C, and when it is mandatory: a `DEVELOPER_DIR` or `runs-on` change, a snapshot library
    bump, or the "Snapshot environment changed" warning.
  - Never commit images recorded on a Mac.
  - The local skip message, and `UNLATCH_SNAPSHOTS=skip`.
- In "2. Confirm `main` is green", add one line: a skipped snapshot suite locally is expected, and
  CI's run is the one that counts.

Acceptance criteria:

- Someone who has never seen the design can re-record from the doc alone. Test this by following it
  on a branch.
- The section links this design.

## 6. Decisions

Decided by the maintainer on 2026-10-15:

1. **Snapshot failures block merges.** The tests run inside the required `build-and-test` job, as the
   issue's scope says. A runner image change that alters rendering is handled with flow C.
2. **T3 is in scope.** The "Update Available" footer gets its two snapshots.
3. **`macos-developer` writes the RELEASING.md section (P1) in the T2 change**, not `project-owner` in a
   separate PR.
4. **Sparkle fetched by `UnlatchCore` consumers:** no action now. If an external consumer appears, file
   it as a separate issue.

All tasks ship as a single PR that says `Closes #28`. D2's dispatch workflow can only be run after that
PR merges.
