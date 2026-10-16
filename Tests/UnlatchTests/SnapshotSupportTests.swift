import Testing

@testable import Unlatch

// The pure parts of the snapshot gate. None of these call `RenderEnvironment.current()` or
// touch a file.

private let sample = RenderEnvironment(
    osVersion: "27.0.1 (26A434)", accentColor: "default", highlightColor: "default",
    increaseContrast: false, reduceTransparency: false)

@Test func snapshotModeParsesTheEnvironment() {
    #expect(SnapshotMode(environment: [:]) == .auto)
    #expect(SnapshotMode(environment: ["UNLATCH_SNAPSHOTS": "require"]) == .require)
    #expect(SnapshotMode(environment: ["UNLATCH_SNAPSHOTS": "skip"]) == .skip)
    #expect(SnapshotMode(environment: ["UNLATCH_SNAPSHOTS": "auto"]) == .auto)
    #expect(SnapshotMode(environment: ["UNLATCH_SNAPSHOTS": "garbage"]) == .auto)
}

@Test func recordModeDefaultsToNever() {
    #expect(recordMode(environment: [:]) == .never)
    #expect(recordMode(environment: ["SNAPSHOT_TESTING_RECORD": "failed"]) == .failed)
    #expect(recordMode(environment: ["SNAPSHOT_TESTING_RECORD": "all"]) == .all)
    #expect(recordMode(environment: ["SNAPSHOT_TESTING_RECORD": "garbage"]) == .never)
}

@Test func requireRunsWhateverTheFingerprint() {
    #expect(snapshotRunDecision(mode: .require, recorded: nil, current: sample) == .run)
    var other = sample
    other.osVersion = "27.1 (26B12)"
    #expect(snapshotRunDecision(mode: .require, recorded: other, current: sample) == .run)
}

@Test func skipAlwaysSkips() {
    guard case .skip = snapshotRunDecision(mode: .skip, recorded: sample, current: sample) else {
        Issue.record("skip mode must skip even on a matching fingerprint")
        return
    }
}

@Test func autoRunsOnAMatchingFingerprint() {
    #expect(snapshotRunDecision(mode: .auto, recorded: sample, current: sample) == .run)
}

@Test func autoSkipsWithoutAFingerprint() {
    guard case .skip(let reason) = snapshotRunDecision(mode: .auto, recorded: nil, current: sample)
    else {
        Issue.record("auto mode must skip without RECORDED_ON.txt")
        return
    }
    #expect(reason.contains("RECORDED_ON.txt"))
    #expect(reason.contains("UNLATCH_SNAPSHOTS=require"))
}

private enum DifferingField: String, CaseIterable, Sendable {
    case macOS, accentColor = "accent color", highlightColor = "highlight color"
    case increaseContrast = "Increase Contrast", reduceTransparency = "Reduce Transparency"

    func apply(to environment: inout RenderEnvironment) {
        switch self {
        case .macOS: environment.osVersion = "27.1 (26B12)"
        case .accentColor: environment.accentColor = "4"
        case .highlightColor: environment.highlightColor = "0.5 0.5 0.5"
        case .increaseContrast: environment.increaseContrast = true
        case .reduceTransparency: environment.reduceTransparency = true
        }
    }
}

@Test(arguments: DifferingField.allCases)
private func autoSkipsWhenOneFieldDiffers(field: DifferingField) {
    var current = sample
    field.apply(to: &current)
    guard case .skip(let reason) = snapshotRunDecision(mode: .auto, recorded: sample, current: current)
    else {
        Issue.record("a differing \(field.rawValue) must skip")
        return
    }
    #expect(reason.contains(field.rawValue))
}

@Test func firstDifferenceNamesTheOSBeforeOtherFields() {
    var current = sample
    current.osVersion = "27.1 (26B12)"
    current.accentColor = "4"
    let reason = sample.firstDifference(from: current)
    #expect(reason?.contains("27.0.1 (26A434)") == true)
    #expect(reason?.contains("27.1 (26B12)") == true)
}

@Test func renderEnvironmentRoundTripsThroughItsFile() {
    #expect(RenderEnvironment(fileContents: sample.fileContents) == sample)
}

@Test func renderEnvironmentWithAMissingKeyIsNil() {
    let missing = sample.fileContents.split(separator: "\n").filter { !$0.hasPrefix("accentColor") }
        .joined(separator: "\n")
    #expect(RenderEnvironment(fileContents: missing) == nil)
    #expect(RenderEnvironment(fileContents: "") == nil)
}

@Test func renderEnvironmentIgnoresUnknownKeys() {
    #expect(RenderEnvironment(fileContents: sample.fileContents + "futureKey=1\n") == sample)
}
