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
