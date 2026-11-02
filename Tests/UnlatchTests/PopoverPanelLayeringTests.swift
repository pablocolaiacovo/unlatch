import AppKit
import Testing

@testable import Unlatch

// The panels' runModal() calls can't be driven from a test, so these cover what
// surrounds them: the hooks that fire around a panel, and the level changes
// those hooks make.

@MainActor
private func makeWindow(level: NSWindow.Level = .statusBar) -> NSWindow {
    let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    window.level = level
    return window
}

@MainActor @Test func theLoweredPopoverSitsBelowTheModalPanel() {
    let window = makeWindow()
    #expect(window.level > .modalPanel, "the status bar level is why the popover covers the panel")

    PopoverPanelLayering().lower(window)

    #expect(window.level < .modalPanel)
    #expect(window.level > .normal, "the popover stays above other apps' normal windows")
}

@MainActor @Test func restoringPutsThePopoverBackAtItsOwnLevel() {
    let window = makeWindow(level: .popUpMenu)
    let layering = PopoverPanelLayering()

    layering.lower(window)
    layering.restore()

    #expect(window.level == .popUpMenu)
}

@MainActor @Test func loweringTwiceStillRestoresTheOriginalLevel() {
    let window = makeWindow()
    let layering = PopoverPanelLayering()

    layering.lower(window)
    layering.lower(window)
    layering.restore()

    #expect(window.level == .statusBar)
}

@MainActor @Test func aReshownPopoverWhoseLevelWasResetIsLoweredAgain() {
    let window = makeWindow()
    let layering = PopoverPanelLayering()

    layering.lower(window)
    window.level = .statusBar  // What AppKit does when the popover shows again.
    layering.lower(window)

    #expect(window.level == PopoverPanelLayering.loweredLevel)

    layering.restore()

    #expect(window.level == .statusBar)
}

@MainActor @Test func aPopoverWithANewWindowBehindThePanelIsLoweredAndBothAreRestored() {
    let closed = makeWindow()
    let reopened = makeWindow()
    let layering = PopoverPanelLayering()

    layering.lower(closed)
    layering.lower(reopened)

    #expect(closed.level == .statusBar, "the closed popover's window can be reused later")
    #expect(reopened.level == PopoverPanelLayering.loweredLevel)

    layering.restore()

    #expect(reopened.level == .statusBar)
}

@MainActor @Test func restoringWithNothingLoweredDoesNothing() {
    let window = makeWindow()
    let layering = PopoverPanelLayering()

    layering.restore()
    layering.lower(nil)
    layering.restore()

    #expect(window.level == .statusBar)
}

@MainActor @Test func panelHooksFireAroundThePanelInOrder() {
    let model = AppModel(loginItemService: FixedLoginItem(status: .unavailable))
    var events: [String] = []
    model.onPanelWillOpen = { events.append("open, presenting: \(model.isPresentingPanel)") }
    model.onPanelDidClose = { events.append("close, presenting: \(model.isPresentingPanel)") }

    let response = model.whilePresentingPanel {
        events.append("panel, presenting: \(model.isPresentingPanel)")
        return 7
    }

    #expect(response == 7)
    #expect(events == [
        "open, presenting: true",
        "panel, presenting: true",
        "close, presenting: false",
    ])
}
