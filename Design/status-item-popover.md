# Status item and popover in AppKit (issue #15)

Issue: #15, "Keep the popover open while dragging PDFs, and accept drops on the menu bar icon"
(`bug`, `release-blocker`, `area:app`, milestone v1.0).

## 1. Summary

The popover is a SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`
(`Sources/Unlatch/UnlatchApp.swift`). When the user presses on a PDF in Finder to start a drag,
Finder activates and the window closes on that mouse-down. By the time a drag session exists,
nothing is left to drop onto, so the "Drop PDFs here" zone in `IdleStepView` does not work from
Finder. `MenuBarExtra` gives no control over dismissal and no access to its `NSStatusItem`.

This change replaces `MenuBarExtra` with an `NSStatusItem` and an `NSPopover` that AppKit owns.
`PopoverView` stays as it is and is hosted in an `NSHostingController`. The popover uses
`.applicationDefined` behaviour, so Unlatch decides when it closes. A left-button press outside the
popover does not close it straight away. Unlatch waits for the button to come up and closes the
popover then, unless a drag reached one of Unlatch's drop targets in the meantime. The status item
button also becomes a drop target that accepts PDFs only.

### Goals

1. `NSStatusItem` + `NSPopover` managed from AppKit, hosting the existing `PopoverView`.
2. The popover stays open while a file drag that started outside it is in progress, so a PDF can be
   dragged from Finder into the in-popover zone. Without a drag, an outside click closes it as today.
3. The status item button accepts PDF file drops. It highlights while a valid drag hovers, rejects
   non-PDFs, routes the URLs into `AppModel.load(_:)`, and opens the popover on drop.
4. Parity with today:
   - The `lock` / `lock.open` glyph follows `hasLockedWork`.
   - `.accessory` activation policy, so no Dock icon.
   - The popover is 372 pt wide.
   - The Quit button and ⌘Q from #19.
   - Light and dark appearance.
   - Clicking the status item toggles the popover.
   - The keyboard works as soon as the popover opens: the password field takes typing, Return
     triggers the default button, and ⌘V pastes.

### Non-goals

- `UnlatchCore` is untouched.
- The look of the in-popover drop zone does not change. Its `dropDestination(for: URL.self)` keeps
  accepting any file URL, and non-PDFs still show as "Not a readable PDF" rows.
- No drops onto a Dock or app icon (the app has no Dock presence).
- No global keyboard shortcut.
- File promises (dragging an attachment out of Mail, or from Photos) are not accepted. They arrive
  as `NSFilePromiseReceiver`, not as file URLs.
- The macOS 27 `NSStatusItem.expandedInterfaceDelegate` API is not adopted. See Trade-offs, T6.
- Making the whole popover a drop target on the password, destination, and done steps. The status
  item covers dropping at any step.

## 2. Design

### 2.1 Module and file map

Everything is in the `Unlatch` target. `UnlatchCore` and `Tests/UnlatchCoreTests` do not change.

| File | Change | Task |
| --- | --- | --- |
| `Sources/Unlatch/UnlatchApp.swift` | Drop `MenuBarExtra`. `body` becomes a `Settings` scene with its menu item removed. `AppDelegate` owns `AppModel` and `StatusItemController`. | 1 |
| `Sources/Unlatch/StatusItemController.swift` (new) | `NSStatusItem`, `NSPopover`, icon rendering via `withObservationTracking`, toggle, present-and-focus, `NSPopoverDelegate`. | 1, 2, 3 |
| `Sources/Unlatch/PopoverHostingController.swift` (new) | `NSHostingController<PopoverView>` subclass: `sizingOptions`, closes on Esc through `cancelOperation(_:)`. | 1 |
| `Sources/Unlatch/PopoverDismissalMonitor.swift` (new) | Global and local event monitors plus notifications that feed the dismissal reducer, and the mouse-up watcher. | 1 (simple), 2 (reducer) |
| `Sources/Unlatch/StatusItemDropView.swift` (new) | Transparent `NSView` overlay on `statusItem.button` that implements `NSDraggingDestination`. | 3 |
| `Sources/Unlatch/AppModel.swift` | Add `hasLockedWork` and the `onLoad` hook. Document `dragging` as zone-only. Rewrite the stale `MenuBarExtra` comments above `browse()` and `chooseOtherFolder()`. | 1 |
| `Sources/Unlatch/Logic.swift` | Pure helpers: `hasLockedWork(_:)`, `statusSymbolName(hasLockedWork:)`, the dismissal reducer, `acceptedPDFDrop(_:)`, `statusItemAcceptsDrop(during:)`. | 1, 2, 3 |
| `Tests/UnlatchTests/StatusItemLogicTests.swift` (new) | Swift Testing tests for the helpers above. | 1, 2, 3 |
| `Package.swift` | Comment only: the macOS 14 floor is now for `@Observable` and `NSApp.activate`, not `MenuBarExtra`. | 1 |
| `Views/*.swift` | No change. | none |

Note on tests: the app's pure logic is already tested in `Tests/UnlatchTests/LogicTests.swift`
(`@testable import Unlatch`), not in `UnlatchCoreTests`. The new tests go next to it. No PDF
fixtures are needed and `Scripts/generate-fixtures.sh` does not change.

### 2.2 App structure (`@main`)

```swift
@main
struct UnlatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A scene is required. Settings opens no window at launch. The "Settings…"
        // item (⌘,) is removed so it cannot open an empty window.
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(model: model)
    }
}
```

Why keep the SwiftUI `App` lifecycle instead of a hand-written `NSApplication.main`: the SwiftUI
lifecycle installs the standard main menu. Its Edit items are how ⌘V, ⌘C, ⌘X, and ⌘A reach the
password field. In an app with no main menu those key equivalents do nothing, and pasting a
password is a core use. The Quit item also keeps ⌘Q working alongside `PopoverView`'s own
`.keyboardShortcut("q")`. With `.accessory` the menu is never shown, but its key equivalents still
fire while the app is active. The model moves from `@State` in `UnlatchApp` to `AppDelegate`
because AppKit (the status item) now needs it too.

If Swift 6 rejects the `AppModel()` stored-property initializer in the delegate's isolation, create
the model in `applicationDidFinishLaunching` instead. Both run on the main actor.

### 2.3 `StatusItemController`

```swift
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    init(model: AppModel)

    /// Button action (sent on .leftMouseDown, as a native menu extra does).
    @objc func togglePopover(_ sender: Any?)
    /// Shows the popover if hidden, then activates the app and makes the popover key.
    /// Idempotent. Called on status item click, on status item drop, and from AppModel.onLoad.
    func presentAndFocus()
    func closePopover()                                    // popover.performClose(nil)

    // NSPopoverDelegate (these methods are main-actor in the SDK)
    func popoverDidShow(_ notification: Notification)      // start dismissal monitor, update highlight
    func popoverDidClose(_ notification: Notification)     // stop monitor, model.dragging = false, update highlight

    private func observeModel()                            // withObservationTracking loop, 2.5
    private func renderButton(hasLockedWork: Bool)
    private func focusPopover()                            // activation + makeKey, 2.6
}
```

Setup:

- `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`.
- The button image is `NSImage(systemSymbolName: statusSymbolName(hasLockedWork:),
  accessibilityDescription: "Unlatch")` with `isTemplate = true`. A template image gives the
  light, dark, and tinted menu bar appearances for free.
- Set `button.toolTip = "Unlatch"`, `button.target` and `button.action`, and
  `button.sendAction(on: [.leftMouseDown])`.
- Leave `behavior` at its default, so the item cannot be removed. An `.accessory` app has no other
  way to bring it back.
- The popover: `behavior = .applicationDefined`, `animates = true`,
  `contentViewController = PopoverHostingController(model:onCancel:)`, `delegate = self`.
- Show it with `popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)`.
- Highlight: `button.highlight(popover.isShown || isDropHovering)`. This is the standard pressed
  look of a menu extra, used both while the popover is open and while a valid drag hovers (task 3).

`PopoverHostingController`:

```swift
final class PopoverHostingController: NSHostingController<PopoverView> {
    init(model: AppModel, onCancel: @escaping @MainActor () -> Void)
    required init?(coder: NSCoder)       // fatalError, not used
    override func cancelOperation(_ sender: Any?)   // Esc: calls onCancel
}
```

In `init`, set `sizingOptions = .preferredContentSize`. The SDK marks it `@available(macOS 13.3)`
on the controller and 13.0 on the option set, both below the macOS 14 target. `NSPopover` then
follows the SwiftUI content height as steps change. The width stays 372 pt from `PopoverView`'s
`.frame(width: 372)`.

One visible change: `NSPopover` draws an anchor arrow and `MenuBarExtra(.window)` does not. See
Open question 1.

### 2.4 Dismissal: `.applicationDefined` plus a deferred decision on mouse-up

#### What each `NSPopover.Behavior` does

Quoted from the `NSPopover.h` doc comments, which are the source of the
[NSPopover.Behavior](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum)
page:

- `.transient`: "AppKit will close the popover when the user interacts with a user interface
  element outside the popover. […] The exact interactions that will cause transient popovers to
  close are not specified." A press in Finder is exactly such an interaction, and it happens on the
  mouse-down, before a drag exists. That is today's bug.
- `.semitransient`: "AppKit will close the popover when the user interacts with user interface
  elements in the window containing the popover's positioning view." For a status item, that window
  is the status bar window, so clicks in Finder or on the desktop would never close the popover.
  That breaks the "closes on an outside click" goal.
- `.applicationDefined` (the default): "Your application assumes responsibility for closing the
  popover. AppKit will still close the popover in a limited number of circumstances […] You may
  consider implementing -cancel: to close the popover when the escape key is pressed."

None of the three gives "stays open during a drag, closes on an outside click" by itself. The
timing problem is structural. At the moment AppKit would close the popover, which is the mouse-down
in another app, nobody can know yet whether that press becomes a click or a drag. The decision can
only be made once the press ends, so it has to be deferred until then.

#### Chosen mechanism

Use `.applicationDefined` and have Unlatch make every close decision. An outside left press moves
the popover into a pending state:

1. Any outside press is detected in one of two ways: a global monitor for `.leftMouseDown`,
   `.rightMouseDown`, and `.otherMouseDown`, or `NSApplication.didResignActiveNotification` with the
   left button held (`NSEvent.pressedMouseButtons & 1`). Either one starts
   `pending(dragReachedUs: false)` and a release watcher. Right and other buttons cannot start a
   file drag, so they close the popover at once.
2. While the press is pending, a drag reaching an Unlatch drop target sets `dragReachedUs = true`.
   There are two drop targets:
   - the in-popover zone, seen when `AppModel.dragging` flips to `true` through the observation
     loop;
   - the status item overlay's `draggingEntered` with an accepted payload (task 3).
3. When the left button comes up, the popover stays open if `dragReachedUs` is true and closes
   otherwise. A plain click in Finder therefore closes the popover on mouse-up instead of
   mouse-down, which is not noticeable in practice. A cancelled drag or a drop somewhere else also
   closes it.
4. Other ways the popover closes:
   - Switching apps with no button held (⌘Tab), through `didResignActiveNotification`, closes it.
   - A Space change, through `NSWorkspace.shared.notificationCenter` and
     `NSWorkspace.activeSpaceDidChangeNotification`, closes it only when nothing is pending.
   - Esc (`PopoverHostingController.cancelOperation`) and a second click on the status item both
     close it.
5. While a modal panel is running (`NSApp.modalWindow != nil`, meaning the `NSOpenPanel` from
   `browse()` or `chooseOtherFolder()`), outside presses and resign-active are ignored. This also
   removes the "Known limitation" in `AppModel`: the file panel no longer dismisses the popover.

How release is detected. `NSEvent` docs: global monitors "receive copies of events posted to other
applications" and do "not [get] called for events that are sent to your own application". Mouse
events need no Accessibility trust. Only key events do
([addGlobalMonitorForEvents(matching:handler:)](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))).
During a Finder drag session, the final mouse-up may go to the drag source or be absorbed by its
tracking loop. A drop that ends on Unlatch's own window would also never reach a global monitor.
So the watcher has three sources:

- a global `.leftMouseUp` monitor (the fast path for plain clicks in other apps);
- a local `.leftMouseUp` monitor;
- a `Task` on the main actor that checks `NSEvent.pressedMouseButtons & 1 == 0` every 50 ms while
  pending, and exits as soon as the state leaves pending.

`pressedMouseButtons` "returns the state of devices … independent of which events have been
delivered", which is what we need here: is the button physically still down? The docs call it
"not suitable for tracking", meaning reconstructing click sequences. We only read the current state
of one button, so that caveat does not apply
([pressedMouseButtons](https://developer.apple.com/documentation/appkit/nsevent/pressedmousebuttons)).
All three sources feed the same `.leftMouseReleased` event, and the reducer ignores it when nothing
is pending, so duplicates are harmless.

Race between drop and release: `AppModel.dragging` becomes `true` when the drag enters the zone,
which is always before the drop and before the mouse-up. The latch is therefore set before the
release is seen. The decision does not depend on whether `performDrop` or the release watcher runs
first.

#### Pure reducer (`Logic.swift`, task 2)

```swift
/// Where an outside press stands while the popover is open.
enum OutsidePress: Equatable, Sendable {
    case none
    case pending(dragReachedUs: Bool)
}

enum DismissalEvent: Equatable, Sendable {
    case outsideMouseDown(isLeftButton: Bool)
    case appDidResignActive(isLeftButtonDown: Bool)
    case leftMouseReleased
    case dropTargetEntered          // in-popover zone or status item, valid payload
    case activeSpaceChanged
}

enum DismissalDecision: Equatable, Sendable {
    case keepOpen, close, watchForRelease
}

func dismissalDecision(
    for event: DismissalEvent,
    press: inout OutsidePress,
    modalPanelOpen: Bool
) -> DismissalDecision
```

Transition table (tests cover every row):

| State | Event | New state | Decision |
| --- | --- | --- | --- |
| any | `outsideMouseDown` / `appDidResignActive` with `modalPanelOpen` | unchanged | keepOpen |
| none | `outsideMouseDown(isLeftButton: true)` | pending(false) | watchForRelease |
| none | `outsideMouseDown(isLeftButton: false)` | none | close |
| none | `appDidResignActive(isLeftButtonDown: true)` | pending(false) | watchForRelease |
| none | `appDidResignActive(isLeftButtonDown: false)` | none | close |
| pending | `outsideMouseDown` / `appDidResignActive` | unchanged | keepOpen |
| pending(_) | `dropTargetEntered` | pending(true) | keepOpen |
| none | `dropTargetEntered` | none | keepOpen |
| pending(true) | `leftMouseReleased` | none | keepOpen |
| pending(false) | `leftMouseReleased` | none | close |
| none | `leftMouseReleased` | none | keepOpen |
| none | `activeSpaceChanged` | none | close |
| pending | `activeSpaceChanged` | unchanged | keepOpen |

`PopoverDismissalMonitor` owns `OutsidePress`, resets it to `.none` in `stop()`, and maps
`.close` to its `close` closure:

```swift
@MainActor
final class PopoverDismissalMonitor {
    init(isModalPanelOpen: @escaping @MainActor () -> Bool,
         close: @escaping @MainActor () -> Void)
    func start()                  // install monitors and observers (on popoverDidShow)
    func stop()                   // remove all, cancel the watcher task, press = .none
    func dropTargetEntered()      // from the controller: zone or status item was targeted
}
```

In task 1 the monitor exists without the reducer: any outside mouse-down, resign-active, or Space
change closes the popover at once. This is today's behaviour. Task 2 swaps in the reducer without
changing the monitor's public API.

### 2.5 Sharing `AppModel` between AppKit and SwiftUI

`AppModel` is `@MainActor @Observable`. The same instance goes to `PopoverView` through the hosting
controller and to `StatusItemController`. There is exactly one owner (`AppDelegate`), which lives
for the whole process.

Additions to `AppModel`:

```swift
/// Closed lock while an encrypted file is loaded and not yet unlocked.
var hasLockedWork: Bool { Unlatch.hasLockedWork(files) }

/// Set by StatusItemController. Called synchronously at the start of every
/// accepted load (in-popover drop, browse, status item drop) so the AppKit layer
/// can show the popover and make it key before the step changes.
@ObservationIgnored var onLoad: (@MainActor () -> Void)?
```

`load(_:)` calls `onLoad?()` right after its `guard !urls.isEmpty`. `dragging` gets a doc comment
saying it is the in-popover drop zone's `isTargeted` state only.

The status item observes the model through `withObservationTracking`, re-armed on every change:

```swift
private func observeModel() {
    withObservationTracking {
        renderButton(hasLockedWork: model.hasLockedWork)
        if model.dragging { dismissalMonitor.dropTargetEntered() }
    } onChange: { [weak self] in
        Task { @MainActor in self?.observeModel() }
    }
}
```

Options considered and why `withObservationTracking` wins:

- `withObservationTracking` is available on macOS 14 and needs no new dependency. It is
  [one-shot by design](https://developer.apple.com/documentation/observation/withobservationtracking(_:onchange:)),
  so it is re-armed from `onChange`. `onChange` is `@Sendable` and fires in `willSet`, so it hops
  back with `Task { @MainActor in … }` and reads the new value on the next main-actor turn.
  `StatusItemController` is `@MainActor`, which makes it `Sendable`, so a `[weak self]` capture is
  fine under strict concurrency.
- The macOS 26 `Observations` async sequence is cleaner but above the deployment target.
- Putting an `NSHostingView` with a SwiftUI `Image` inside the status bar button was rejected. It
  fights `NSStatusBarButton`'s sizing, template tinting, and highlight drawing, and it would sit in
  the same view hierarchy as the drop overlay.
- A `didSet` callback on `files` was rejected. It duplicates what Observation already does and is
  easy to miss when a new mutation path is added.

#### Shared `dragging` flag (issue note 3)

The icon and the zone keep separate state. `AppModel.dragging` stays the in-popover zone's flag and
nothing else sets it. The status item's hover state is a private `isDropHovering` on the
controller, shown only through `button.highlight(_:)`. Hovering the icon does not light up the zone,
for three reasons:

- The popover may be closed, or on a step with no zone.
- The two are different targets, and lighting the zone implies "drop here".
- Keeping AppKit hover state out of the observable model avoids re-rendering SwiftUI on every drag
  event over the menu bar.

Both still count as "a drag reached us" for the dismissal reducer, which is the only place that
needs the combined signal.

### 2.6 Keyboard focus (issue note 1)

Under `.accessory`, an `NSPopover` from a status item is not key unless the app is active. Without a
key window, the password field ignores typing and `.keyboardShortcut(.defaultAction)` does not
fire. `focusPopover()` does both steps, in this order:

```swift
NSApp.activate(ignoringOtherApps: true)
popover.contentViewController?.view.window?.makeKey()
```

`presentAndFocus()` calls it after `show(relativeTo:of:preferredEdge:)` in three cases:

- a status item click;
- a status item drop;
- `AppModel.onLoad`, which covers a drop into the in-popover zone while Finder is frontmost, and a
  return from `browse()`.

Why the timing works for the password step: `load(_:)` runs `onLoad` synchronously, then classifies
in a detached task. The popover is key before `step` becomes `.password`, so `PasswordStepView`'s
existing `.onAppear { focusedField = .secure }` lands in a key window.

Why `activate(ignoringOtherApps: true)` rather than the macOS 14 `activate()`:

- The header marks the old call `API_TO_BE_DEPRECATED` ("will be deprecated in a future release"),
  which produces no warning today. It is documented as "If YES, the app activates regardless".
- The new `activate()` is cooperative: "The framework also does not guarantee that the app will be
  activated at all"
  ([NSApplication.activate()](https://developer.apple.com/documentation/appkit/nsapplication/activate())).
  After a drop from Finder, Finder is active and has not yielded activation, so the cooperative call
  can be refused. The user would then land on a password field they cannot type into.
- `AppModel.browse()` already uses the same call.

Keep the call inside `focusPopover()` so that moving to `activate()` later is a one-line change.

### 2.7 Status item as a drop target (task 3)

`NSStatusBarButton` is created by `NSStatusItem`, so it cannot be subclassed. The recommended
approach is a transparent overlay subview:

```swift
@MainActor
final class StatusItemDropView: NSView {
    init(canAcceptDrop: @escaping @MainActor () -> Bool,        // statusItemAcceptsDrop(during: model.step)
         onHoverChanged: @escaping @MainActor (Bool) -> Void,   // highlight + dismissal latch
         onDrop: @escaping @MainActor ([URL]) -> Void)          // model.load + presentAndFocus

    override func hitTest(_ point: NSPoint) -> NSView?          // nil: clicks fall through to the button
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation   // .copy or []
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation   // same verdict
    override func draggingExited(_ sender: NSDraggingInfo?)
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool
    override func draggingEnded(_ sender: NSDraggingInfo)      // clear hover in all cases
}
```

- It is added to `statusItem.button` with `frame = button.bounds` and
  `autoresizingMask = [.width, .height]`, and it calls `registerForDraggedTypes([.fileURL])`.
- The payload is read with `sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []`, then passed through
  `acceptedPDFDrop(_:)`. The same verdict is used in `draggingEntered`, `draggingUpdated`, and
  `performDragOperation`, so the highlight never promises what the drop would refuse.
- A rejected drag gets `[]`: no highlight and the standard slide-back.
- The `NSDraggingDestination` methods are main-actor in the SDK. `NSDraggingInfo` is not `Sendable`
  and never leaves them. Only `[URL]`, which is `Sendable`, goes to `onDrop`.

Drop flow:

1. `performDragOperation` calls `onDrop(urls)`.
2. `onDrop` calls `model.load(urls)`.
3. `load` fires `onLoad`, and `presentAndFocus()` shows the popover and makes it key.
4. Classification finishes and `step` moves to `.password` or `.destination`.

The popover can show the previous step for a moment before the new step replaces it.

Pure helpers (`Logic.swift`, adds `import UniformTypeIdentifiers`):

```swift
/// True for a file URL (not a directory) whose extension's UTType conforms to .pdf.
func isDroppablePDF(_ url: URL) -> Bool

/// The URLs to load, or nil to reject the whole drag: empty, or any item not a PDF.
func acceptedPDFDrop(_ urls: [URL]) -> [URL]?

/// The status item refuses drops while a save or password check is running;
/// load(_:) would replace `files` under the in-flight task.
func statusItemAcceptsDrop(during step: Step) -> Bool     // step != .working

func hasLockedWork(_ files: [LoadedFile]) -> Bool         // moved from UnlatchApp
func statusSymbolName(hasLockedWork: Bool) -> String      // "lock" : "lock.open"
```

`isDroppablePDF` checks the extension, not `resourceValues(.contentTypeKey)`. It stays pure, it
decides at hover time with no disk I/O, and it matches `NSOpenPanel.allowedContentTypes = [.pdf]`
in practice. Finder file URLs for folders carry a trailing slash (`hasDirectoryPath`), which keeps a
folder named `x.pdf` out.

Mixed drags, for example two PDFs and a JPEG, are rejected as a whole. The issue says "reject
non-PDF drags rather than accepting and silently skipping them", and all-or-nothing is the only rule
where the hover highlight states the outcome truthfully. See Open question 2.

Fallback if the overlay does not receive drags: AppKit's drag destination lookup is not documented
to use `hitTest(_:)`. If manual testing shows that returning `nil` stops drag delivery, remove the
`hitTest` override and have the overlay handle `mouseDown(with:)` itself by calling the controller's
`togglePopover`. The button's highlight is already driven by the controller. Do not use the
alternative of setting the status bar window's `delegate`, because that window belongs to AppKit.

### 2.8 Concurrency model

- Every new type is `@MainActor`: `StatusItemController`, `PopoverHostingController` (inherited
  from `NSHostingController`), `PopoverDismissalMonitor`, and `StatusItemDropView`. `AppModel` is
  already `@MainActor`. The only work off the main actor is the existing detached tasks in
  `AppModel`, which do not change.
- Event monitor handlers are not guaranteed `@MainActor` by the Swift signature. They run on the
  main thread, so wrap the bodies in `MainActor.assumeIsolated { … }`. Extract only `Sendable`
  values (`event.type`, the button number) and do not let `NSEvent` escape. Store monitor tokens as
  `Any?` and remove them in `stop()`.
- Register notification observers with `queue: .main` and the same `assumeIsolated` wrapper. Or use
  `for await` over `NotificationCenter.notifications(named:)` in a main-actor `Task` that `stop()`
  cancels. Either is fine; the developer picks one and uses it throughout.
- The release watcher is a main-actor `Task` with `try await Task.sleep(for: .milliseconds(50))`,
  cancelled in `stop()` and when the press leaves pending. Do not use `Timer`, whose block is
  `@Sendable`.
- Do not clean up in `deinit`, which is nonisolated. The controller lives for the whole process.
- Values that cross between layers are `[URL]`, `Bool`, `Step`, and the reducer enums, all
  `Sendable`.

### 2.9 Edge cases

| Case | Behaviour |
| --- | --- |
| Press in Finder, drag into the zone, drop | Kept open. `onLoad` activates and focuses. Password step, typing works. |
| Press in Finder, drag into the zone, drag back out, drop on the desktop | Kept open, because the latch is set. The popover is not key. The next outside click closes it. |
| Press in Finder, drag, cancel with Esc or drop back in Finder without reaching Unlatch | Closes on release. |
| Plain click in Finder or on the desktop | Closes on mouse-up. |
| Right-click anywhere outside | Closes at once. |
| ⌘Tab away | Closes (resign-active with no button held). |
| Click another app's menu extra | Pending until release, then closes. |
| Mission Control or a Space change with nothing pending | Closes. |
| Drag carried across Spaces while pending | Stays pending, and release decides. |
| `NSOpenPanel` from browse or choose folder | The popover stays open. Outside presses are ignored while the panel is modal. |
| Drop on the icon during `.working` | Refused, with no highlight. |
| Drop on the icon on any other step | Replaces the batch, same as a zone drop at idle. |
| Drop on the icon while the popover is closed | Opens and focuses the popover. |
| Two quick drops (icon then zone) | Existing `loadGeneration` guard in `AppModel.load` keeps the newest. |
| Multiple displays | The popover is shown relative to `statusItem.button`, which AppKit moves to the menu bar that was clicked. The icon on a secondary display must also accept drops (manual check). |
| Full-screen app Space | The popover must appear over it when opened from the auto-hidden menu bar (manual check). |

### 2.10 Assumptions

- No sandbox. The app is ad-hoc signed and distributed on GitHub (`RELEASING.md`). Dropped file URLs
  are read directly. If sandboxing is added later, drag-and-drop grants access to dropped files, so
  this design still holds.
- No new entitlements, no Accessibility permission (mouse events only in global monitors), and no
  `Info.plist` change. `.accessory` is still set at runtime.
- Build toolchain: CI builds with Xcode 26.6 (macOS 26 SDK, `.github/workflows/ci.yml`). This
  machine has the macOS 27 SDK. Do not reference macOS 27 symbols; they would build locally and
  fail in CI.

## 3. Trade-offs

**T1: Dismissal mechanism.**

*Chosen: `.applicationDefined` plus the reducer.* Every close path belongs to Unlatch, is decided in
one pure function, and has tests. The Apple contract for this behaviour is explicit ("your
application assumes responsibility"). The cost is roughly 100 lines of monitor wiring and handling
Esc, ⌘Tab, and Space changes ourselves, all listed in 2.4.

Rejected alternatives:

- *`.transient` plus a veto in `popoverShouldClose(_:)` while the left button is down.* This is less
  code and keeps AppKit's own close triggers. But it still needs the same release watcher, because
  after a veto AppKit does not try again and Unlatch has to close the popover itself. Dismissal
  would then be split between AppKit's triggers, documented as "not specified", and ours. It also
  relies on the veto being consulted for every transient close. The header says the delegate is
  asked "whenever it is about to close", but Apple does not document the timing of the transient
  trigger relative to the press. If task 2's manual checks show a hole in the chosen design, this is
  the fallback.
- *`.semitransient`.* It does not close on clicks in other apps (quoted in 2.4).
- *Let it close and reopen when a drag reaches the icon.* The zone disappears from under the
  cursor, which breaks the issue's explicit acceptance criterion for the in-popover zone.

**T2: Status item drop target.**

- *Chosen: an overlay subview.* The button keeps its native appearance and click handling.
- *`statusItem.view` with a custom view:* rejected. The header says `button` "is preferred in most
  cases as it can alter its appearance automatically". A custom view would have to redo template
  tinting and the highlight.
- *Taking over the status bar window's `delegate`:* rejected, because AppKit owns that window.

**T3: Observation.** `withObservationTracking` is chosen over a SwiftUI-hosted icon and over
`didSet` callbacks. See 2.5.

**T4: App shell.** A SwiftUI `App` with a `Settings` scene is chosen over a pure AppKit `main`,
because it keeps the standard Edit and Quit key equivalents. See 2.2.

**T5: Activation call.** `activate(ignoringOtherApps: true)` is chosen over the cooperative
`activate()`. See 2.6.

**T6: macOS 27 `NSStatusItem.expandedInterfaceDelegate`.** The macOS 27 SDK adds
`NSStatusItemExpandedInterfaceDelegate` and `NSStatusItemExpandedInterfaceSession` (`NSStatusItem.h`).
Status items that show their own window can use them to take part in menu bar keyboard navigation
and menu tracking. That corrects the premise in the issue that nothing was added up to macOS 27.
The API does not control dismissal: the header tells the app to cancel the session itself on an
outside click. It is macOS 27-only and does not compile with CI's Xcode 26.6. Worth a Backlog issue
once CI moves to Xcode 27.

## 4. Testing strategy

### Unit tests

In `Tests/UnlatchTests/StatusItemLogicTests.swift`, using Swift Testing and `@testable import
Unlatch`:

- `hasLockedWork`:
  - an empty list is false;
  - an encrypted file not yet unlocked is true;
  - encrypted and unlocked is false;
  - owner-only or corrupt files are false;
  - a mix with one pending encrypted file is true.
- `statusSymbolName` returns `lock` or `lock.open`.
- `isDroppablePDF`:
  - accepts `a.pdf` and `A.PDF`;
  - rejects `a.jpg`, a name with no extension, an `https://…/a.pdf` URL, and a directory URL
    `file:///tmp/x.pdf/`.
- `acceptedPDFDrop`:
  - all PDFs returns them in order;
  - an empty list returns `nil`;
  - a mix returns `nil`;
  - a single non-PDF returns `nil`.
- `statusItemAcceptsDrop(during:)`: false only for `.working`.
- `dismissalDecision`: one test per row of the table in 2.4, plus two sequences:
  - down, targeted, released gives keepOpen;
  - down, released gives close.

No PDF fixtures are needed, and `Scripts/generate-fixtures.sh` does not grow.

### Manual checks

AppKit wiring, activation, and real drags can only be checked by hand. Run `swift run Unlatch`, or
the packaged app once `Scripts/package-app.sh` exists. Test on macOS 14 if a machine is available,
and on the current macOS.

1. **Finder repro (the bug).**
   1. Open the popover.
   2. Press on a user-locked PDF in a Finder window. The popover stays visible.
   3. Drag it into the zone. The zone highlights.
   4. Drop. The popover stays, the password step appears, typing goes into the field without a
      click, and Return submits.
2. The same, starting from a PDF on the desktop.
3. Press on a PDF, drag it around, then press Esc to cancel the drag. The popover closes on
   release.
4. Press on a PDF and drop it into another Finder folder. The popover closes on release, and the
   file moves as usual.
5. Plain click in Finder, on the desktop, or in another app's window. The popover closes.
   Right-click also closes it.
6. ⌘Tab away closes it. Switching Space or opening Mission Control closes it.
7. **Icon drop, popover closed.**
   1. Drag one PDF onto the icon. It highlights.
   2. Drop. The popover opens on the password or destination step with keyboard focus.
8. Drag a JPEG, a folder, or two PDFs plus a JPEG onto the icon. No highlight, the drag slides back,
   and nothing loads.
9. Drag a PDF onto the icon while the popover is open on the destination step. The batch is
   replaced. During "Unlocking…" the icon refuses the drop.
10. Hover the icon with a PDF while the popover is open on idle. The zone does not highlight.
11. **Parity.**
    - The icon shows `lock` after loading an encrypted PDF and `lock.open` after saving or Cancel.
    - The icon looks correct in a light and a dark menu bar and with a tinted wallpaper.
    - No Dock icon.
    - The width is 372 pt and the height follows each step.
    - The popover looks correct in light and dark mode.
    - ⌘Q and the power button quit.
    - Clicking the icon toggles the popover.
    - Esc closes it.
    - ⌘V pastes a password.
    - Return triggers Unlock, Save, and Done on their steps.
12. "Click to browse" opens `NSOpenPanel`. The popover stays open behind it. Choosing files lands on
    the next step with focus. The same with "Choose folder…".
13. Two displays: open the popover from, and drop onto, the icon on the secondary display's menu
    bar.
14. Full-screen app: open the popover from the auto-hidden menu bar, and drag a PDF from a Finder
    window in Split View into the zone.

Follow-up for `project-owner`: add item 1 and item 7 to the beta smoke test in `RELEASING.md`.
That file belongs to `project-owner`, so this design does not change it.

## 5. Implementation plan

Three PRs on `fix/` or `feature/` branches off `main`. Each leaves the app working and ends with a
clean `swift build` and a passing `swift test`. Suggested PR titles follow the changelog convention.
Type labels are `project-owner`'s call. Tasks 1 and 2 say `Part of #15`; task 3 says `Closes #15`.

### Task 1: Host the popover in AppKit, at parity

Suggested title: "Show the menu bar panel as a native popover".

- `UnlatchApp.swift`: remove `MenuBarExtra`, add the `Settings` scene without its menu item, and
  move the model into `AppDelegate`.
- Add `StatusItemController`, `PopoverHostingController`, and `PopoverDismissalMonitor` in its
  simple form: any outside mouse-down, resign-active, or Space change closes the popover.
- Add `AppModel.hasLockedWork` and `onLoad`, and the `Logic.swift` helpers `hasLockedWork(_:)` and
  `statusSymbolName(hasLockedWork:)`.
- Refresh the stale `MenuBarExtra` comments in `AppModel` and the `Package.swift` comment.
- Tests for the two helpers.

Acceptance criteria:

- Manual checks 5, 6, 11, and 12 pass. The Finder repro still fails at this point, as it does
  today.
- Grepping `Sources/` for `MenuBarExtra` returns nothing.
- No new warnings.

### Task 2: Keep the popover open while a file drag is in progress

Depends on task 1. Suggested title: "Keep the popover open while dragging PDFs in from Finder".

- Add `OutsidePress`, `DismissalEvent`, `DismissalDecision`, and `dismissalDecision(for:press:modalPanelOpen:)`
  to `Logic.swift`, with the table tests.
- Switch `PopoverDismissalMonitor` to the reducer, add the three release sources, and add the modal
  panel guard.
- The controller's observation loop feeds `dropTargetEntered()` from `model.dragging`.

Acceptance criteria:

- Manual checks 1 to 6 and 12 pass.
- Every row of the reducer table has a test.

If checks 1 to 4 show the global monitor sees neither the press nor the resign-active in some
flow, record the flow in the PR and stop. Do not switch to `.transient` without going back to
`architect`.

### Task 3: Accept PDFs dropped onto the menu bar icon

Depends on task 2 for the latch; the drop itself only depends on task 1.

- Add `StatusItemDropView`.
- Add `isDroppablePDF`, `acceptedPDFDrop`, and `statusItemAcceptsDrop(during:)` with tests.
- Controller wiring: `isDropHovering` drives the highlight, a hover calls `dropTargetEntered()`, and
  a drop calls `model.load(urls)` followed by `presentAndFocus()`.
- Verify the `hitTest` question from 2.7 first thing in the session. If the overlay gets no
  drags, apply the documented fallback.

Acceptance criteria:

- Manual checks 7 to 10 and 13 pass, and checks 1 and 11 still pass.
- The PR body says `Closes #15`.

## 6. Decisions from the maintainer

The maintainer approved all three recommendations below. They are decisions, not open questions;
later tasks and any future revisit are tracked as separate Backlog issues rather than reopening
this design.

1. **Popover arrow.** `NSPopover` draws an anchor arrow that `MenuBarExtra(.window)` did not.
   Removing it means either private API or a borderless `NSPanel` with hand-built material and
   positioning, which is much more code and more risk for a v1.0 blocker. **Decided: accept the
   arrow.** It is the standard look for menu bar popovers.
2. **Mixed drags onto the icon.** For two PDFs plus a JPEG, the options are to reject the whole drag
   or to accept only the PDFs. **Decided: reject the whole drag**, as designed. It follows the
   issue's wording, and the highlight never promises something the drop won't do. The in-popover
   zone is out of scope and keeps accepting anything, showing non-PDFs as unreadable rows. Aligning
   the two can be a Backlog issue if wanted.
3. **Icon drop mid-flow.** Dropping on the icon while on the password, destination, or done step
   replaces the current batch and discards a typed password. **Decided: allow it** (only `.working`
   refuses). A drop is an explicit request to work on new files.
