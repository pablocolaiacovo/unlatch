import Foundation
import Testing
@testable import Unlatch

// Pure logic behind the Sparkle updater (Design/sparkle-updates.md, §2.5).

private let appURL = URL(fileURLWithPath: "/Applications/Unlatch.app")
private let feed = "https://example.com/appcast.xml"
private let key = "c2VjcmV0"

// MARK: - updaterAvailability

@Test func updaterIsEnabledForAnAppBundleWithHTTPSFeedAndKey() {
    #expect(updaterAvailability(bundleURL: appURL, feedURL: feed, publicEDKey: key) == .enabled)
}

@Test func updaterIsDisabledOutsideAnAppBundleEvenWithBothKeys() {
    let url = URL(fileURLWithPath: "/tmp/.build/debug")
    #expect(
        updaterAvailability(bundleURL: url, feedURL: feed, publicEDKey: key)
            == .disabled(.notAnAppBundle))
}

@Test(arguments: [nil, ""] as [String?])
func updaterIsDisabledWithoutAFeed(missing: String?) {
    #expect(
        updaterAvailability(bundleURL: appURL, feedURL: missing, publicEDKey: key)
            == .disabled(.missingFeedURL))
}

@Test(arguments: ["http://example.com/appcast.xml", "not a url", "ftp://example.com/a.xml", "https://"])
func updaterIsDisabledForANonHTTPSFeed(bad: String) {
    #expect(
        updaterAvailability(bundleURL: appURL, feedURL: bad, publicEDKey: key)
            == .disabled(.insecureFeedURL))
}

@Test(arguments: [nil, ""] as [String?])
func updaterIsDisabledWithoutAPublicKey(missing: String?) {
    #expect(
        updaterAvailability(bundleURL: appURL, feedURL: feed, publicEDKey: missing)
            == .disabled(.missingPublicKey))
}

@Test func updaterReportsTheFirstProblemInDocumentedOrder() {
    let notApp = URL(fileURLWithPath: "/tmp/Unlatch")
    #expect(
        updaterAvailability(bundleURL: notApp, feedURL: nil, publicEDKey: nil)
            == .disabled(.notAnAppBundle))
    #expect(
        updaterAvailability(bundleURL: appURL, feedURL: nil, publicEDKey: nil)
            == .disabled(.missingFeedURL))
    #expect(
        updaterAvailability(bundleURL: appURL, feedURL: "http://x.com", publicEDKey: nil)
            == .disabled(.insecureFeedURL))
}

// MARK: - allowedUpdateChannels

@Test(arguments: ["1.1.0", "0.0.0-abc1234", "1.1.0-betamax"])
func stableLookingVersionsFollowOnlyTheDefaultChannel(version: String) {
    #expect(allowedUpdateChannels(forVersion: version).isEmpty)
}

@Test func missingVersionFollowsOnlyTheDefaultChannel() {
    #expect(allowedUpdateChannels(forVersion: nil).isEmpty)
}

@Test(arguments: ["1.1.0-beta.1", "1.1.0-beta.2-3-gabc1234-dirty"])
func betaVersionsFollowTheBetaChannel(version: String) {
    #expect(allowedUpdateChannels(forVersion: version) == ["beta"])
}

// MARK: - updateButtonState

@Test func buttonIsHiddenWheneverTheUpdaterIsDisabled() {
    for reason in [
        UpdaterDisabledReason.notAnAppBundle, .missingFeedURL, .insecureFeedURL, .missingPublicKey,
    ] {
        for canCheck in [true, false] {
            for available in [true, false] {
                #expect(
                    updateButtonState(
                        availability: .disabled(reason), canCheck: canCheck,
                        updateAvailable: available) == .hidden)
            }
        }
    }
}

@Test func buttonIsDisabledWhenSparkleCannotCheck() {
    #expect(
        updateButtonState(availability: .enabled, canCheck: false, updateAvailable: false)
            == .checkDisabled)
}

@Test func buttonStaysDisabledEvenWhenAnUpdateIsWaiting() {
    #expect(
        updateButtonState(availability: .enabled, canCheck: false, updateAvailable: true)
            == .checkDisabled)
}

@Test func buttonOffersACheckWhenNothingIsWaiting() {
    #expect(
        updateButtonState(availability: .enabled, canCheck: true, updateAvailable: false)
            == .check)
}

@Test func buttonAnnouncesAWaitingUpdate() {
    #expect(
        updateButtonState(availability: .enabled, canCheck: true, updateAvailable: true)
            == .updateAvailable)
}

// MARK: - updateFooterPresentation

@Test func hiddenUpdaterLeavesTheMenuItemAndIndicatorOut() {
    let presentation = updateFooterPresentation(for: .hidden)
    #expect(presentation.menuItemTitle == nil)
    #expect(presentation.showsUpdateIndicator == false)
}

@Test func disabledCheckShowsADisabledItemWithoutIndicator() {
    let presentation = updateFooterPresentation(for: .checkDisabled)
    #expect(presentation.menuItemTitle == "Check for Updates…")
    #expect(presentation.menuItemEnabled == false)
    #expect(presentation.showsUpdateIndicator == false)
}

@Test func enabledCheckShowsAnEnabledItemWithoutIndicator() {
    let presentation = updateFooterPresentation(for: .check)
    #expect(presentation.menuItemTitle == "Check for Updates…")
    #expect(presentation.menuItemEnabled == true)
    #expect(presentation.showsUpdateIndicator == false)
}

@Test func waitingUpdateShowsTheIndicatorAndTheUpdateTitle() {
    let presentation = updateFooterPresentation(for: .updateAvailable)
    #expect(presentation.menuItemTitle == UpdateFooterPresentation.updateAvailableTitle)
    #expect(presentation.menuItemEnabled == true)
    #expect(presentation.showsUpdateIndicator == true)
}

@Test func footerCopyEndsInASingleEllipsisCharacter() {
    #expect(UpdateFooterPresentation.checkTitle == "Check for Updates\u{2026}")
    #expect(UpdateFooterPresentation.updateAvailableTitle == "Update Available\u{2026}")
}

@Test func swiftRunShowsNoUpdateUIEndToEnd() {
    let state = updateButtonState(
        availability: .disabled(.notAnAppBundle), canCheck: true, updateAvailable: true)
    let presentation = updateFooterPresentation(for: state)
    #expect(presentation.menuItemTitle == nil)
    #expect(presentation.showsUpdateIndicator == false)
}

// MARK: - Gentle reminders (T8)

@Test(arguments: [true, false])
func sparkleNeverShowsAScheduledUpdateItself(inImmediateFocus: Bool) {
    #expect(sparkleShowsScheduledUpdate(inImmediateFocus: inImmediateFocus) == false)
}

@Test(arguments: [true, false], [true, false])
func aScheduledUpdateRaisesTheIndicatorWhoeverShowsIt(handledBySparkle: Bool, current: Bool) {
    let event = UpdateReminderEvent.willShowUpdate(
        handledBySparkle: handledBySparkle, userInitiated: false)
    #expect(updateIndicatorShown(after: event, current: current) == true)
}

@Test(arguments: [true, false])
func aUserInitiatedUpdateLeavesTheIndicatorAlone(current: Bool) {
    let event = UpdateReminderEvent.willShowUpdate(handledBySparkle: true, userInitiated: true)
    #expect(updateIndicatorShown(after: event, current: current) == current)
}

@Test(arguments: [UpdateReminderEvent.userAttention, .sessionFinished], [true, false])
func attentionAndSessionEndClearTheIndicator(event: UpdateReminderEvent, current: Bool) {
    #expect(updateIndicatorShown(after: event, current: current) == false)
}

@Test func foundThenSeenUpdateRaisesAndClearsTheFooterButton() {
    let found = updateIndicatorShown(
        after: .willShowUpdate(handledBySparkle: false, userInitiated: false), current: false)
    #expect(
        updateButtonState(availability: .enabled, canCheck: true, updateAvailable: found)
            == .updateAvailable)
    #expect(updateIndicatorShown(after: .userAttention, current: found) == false)
}

// MARK: - automaticChecksMenuItem

@Test(arguments: [true, false])
func automaticChecksItemIsShownWhenTheUpdaterIsEnabled(isOn: Bool) {
    #expect(
        automaticChecksMenuItem(availability: .enabled, isOn: isOn)
            == AutomaticChecksMenuItem(title: "Check Automatically", isChecked: isOn))
}

@Test(arguments: [
    UpdaterDisabledReason.notAnAppBundle, .missingFeedURL, .insecureFeedURL, .missingPublicKey,
])
func automaticChecksItemIsHiddenWhenTheUpdaterIsDisabled(reason: UpdaterDisabledReason) {
    #expect(automaticChecksMenuItem(availability: .disabled(reason), isOn: true) == nil)
    #expect(automaticChecksMenuItem(availability: .disabled(reason), isOn: false) == nil)
}

@Test func automaticChecksTitleHasNoEllipsis() {
    #expect(AutomaticChecksMenuItem.checkAutomaticallyTitle == "Check Automatically")
}
