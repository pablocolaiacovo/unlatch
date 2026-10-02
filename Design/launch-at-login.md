# Launch at Login (issue #16)

Issue: #16, "Add a Launch at Login option" (`enhancement`, `area:app`, milestone Backlog).

## Summary

An "Open at Login" checkbox in the popover footer, between the version and Quit. It registers the
app bundle itself with `SMAppService.mainApp` (ServiceManagement, macOS 13+). There is no helper app,
no launch agent plist, and no entitlement change.

## Decisions

**The system is the only store.** The issue asks for the setting to be "persisted in `UserDefaults`"
and also for the checkbox to "reflect the real system state rather than the stored preference". These
conflict: the login item registration already persists across launches, and a second copy in
`UserDefaults` is exactly what goes stale when the user changes System Settings > General > Login
Items. So nothing is written to `UserDefaults`. The checkbox reads `SMAppService.mainApp.status` at
launch and every time the popover opens (`StatusItemController.presentAndFocus()`), and again after
every toggle.

**Status mapping** (`LoginItemStatus` in `Logic.swift`, mapped from `SMAppService.Status` in
`LoginItem.swift`):

| `SMAppService.Status` | `LoginItemStatus` | Checkbox | Checking it | Unchecking it |
| --- | --- | --- | --- | --- |
| `.enabled` | `.enabled` | on | — | `unregister()` |
| `.notRegistered` | `.disabled` | off | `register()` | — |
| `.requiresApproval` | `.requiresApproval` | off, help text points to Login Items | opens Login Items | `unregister()` |
| `.notFound`, unknown, or no bundle identifier | `.unavailable` | off, disabled | — | — |

`.requiresApproval` means the item is registered but switched off in System Settings. The app cannot
turn it back on; only the user can, so checking the box opens Login Items with
`SMAppService.openSystemSettingsLoginItems()` rather than pretending to succeed. The checkbox shows
"off" because Unlatch will not open at login in that state.

**Failures snap back.** `register()` and `unregister()` errors are logged with `NSLog`, and the
status is re-read, so the checkbox always ends on what the system reports.

**`swift run` is `.unavailable`.** `SMAppService.mainApp` needs a real bundle. Without a bundle
identifier the checkbox is disabled with a help tooltip, instead of offering something that fails.

## Testability

`LoginItemService` is a `@MainActor` protocol; `SystemLoginItem` is the only real conformer.
`AppModel.init(loginItemService:)` defaults to it and tests pass a fake. Pure mapping functions
`loginItemControl(for:)` and `loginItemAction(from:turningOn:)` live in `Logic.swift` and are unit
tested in `Tests/UnlatchTests/LoginItemTests.swift`, along with `AppModel` against the fake.

## Manual checks (maintainer, on a Mac)

Use a bundle from `Scripts/package-app.sh`, copied to `/Applications` and launched from there (not
from `dist/`, and not translocated).

1. Check "Open at Login". macOS shows its "Login Item Added" notification, and Unlatch is listed in
   System Settings > General > Login Items.
2. Log out and log back in. The lock icon appears in the menu bar without launching Unlatch by hand.
3. Switch Unlatch off in Login Items, then open the popover. The checkbox is unchecked. Checking it
   opens Login Items.
4. Uncheck "Open at Login". Unlatch disappears from Login Items, and after logging out and in it does
   not start.
5. Under `swift run`, the checkbox is disabled.

Risk to watch in check 1: the bundle is ad-hoc signed (no Team ID). If `register()` fails or the
login item does not launch for an ad-hoc signed app on some macOS version, record the error from
Console (`Unlatch: changing the login item failed`) on #16 and treat it as a dependency on #8
(Developer ID signing) rather than working around it.
