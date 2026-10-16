import AppKit
import CoreImage
import Foundation
import SnapshotTesting
import Testing

@testable import Unlatch

// Support for the popover snapshot tests. See Design/snapshot-tests.md.
//
// Reference images are recorded by CI only. Nothing here writes into the source tree unless
// SNAPSHOT_TESTING_RECORD asks for it, and locally the suite runs only when this Mac renders
// the way the machine that recorded the references did.

// MARK: - Tolerance

/// `precision` allows at most 0.01% of pixels (about 42 on the idle render) to differ by more
/// than a CIE Lab delta E of 2, which is less than one 11 pt glyph at 2x. 0.9998 already misses
/// a one-glyph change, so never loosen below it, and never loosen `perceptualPrecision`.
/// To loosen `precision` after a real flake, check the difference image first and record the
/// reason here.
enum SnapshotTolerance {
    static let precision: Float = 0.9999
    static let perceptualPrecision: Float = 0.98
}

// MARK: - Modes and the local gate

/// `UNLATCH_SNAPSHOTS`: `require` (CI) always runs the suite, `skip` never does, and `auto`
/// (the default, also for unrecognised values) runs it only when this Mac's rendering
/// environment matches the one in `RECORDED_ON.txt`.
enum SnapshotMode: Equatable, Sendable {
    case auto, require, skip

    init(environment: [String: String]) {
        switch environment["UNLATCH_SNAPSHOTS"] {
        case "require": self = .require
        case "skip": self = .skip
        default: self = .auto
        }
    }
}

/// `SNAPSHOT_TESTING_RECORD`, defaulting to `.never`. The library's own default is `missing`,
/// which would silently write references on a developer Mac.
func recordMode(environment: [String: String]) -> SnapshotTestingConfiguration.Record {
    environment["SNAPSHOT_TESTING_RECORD"]
        .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:)) ?? .never
}

/// What affects pixels on a given Mac besides the code: the OS build, and the system-wide
/// settings that change control colours or contrast.
struct RenderEnvironment: Equatable, Sendable {
    var osVersion: String
    var accentColor: String
    var highlightColor: String
    var increaseContrast: Bool
    var reduceTransparency: Bool

    @MainActor static func current() -> RenderEnvironment {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = kernelOSVersion() ?? "unknown"
        let workspace = NSWorkspace.shared
        return RenderEnvironment(
            osVersion:
                "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(build))",
            accentColor: globalPreference("AppleAccentColor"),
            highlightColor: globalPreference("AppleHighlightColor"),
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
    }

    /// `key=value` lines. Returns nil when a key is missing; unknown keys are ignored so the
    /// format can grow.
    init?(fileContents: String) {
        var values: [String: String] = [:]
        for line in fileContents.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            values[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        guard
            let osVersion = values["osVersion"],
            let accentColor = values["accentColor"],
            let highlightColor = values["highlightColor"],
            let increaseContrast = values["increaseContrast"].flatMap(Bool.init),
            let reduceTransparency = values["reduceTransparency"].flatMap(Bool.init)
        else { return nil }
        self.init(
            osVersion: osVersion, accentColor: accentColor, highlightColor: highlightColor,
            increaseContrast: increaseContrast, reduceTransparency: reduceTransparency)
    }

    init(
        osVersion: String, accentColor: String, highlightColor: String,
        increaseContrast: Bool, reduceTransparency: Bool
    ) {
        self.osVersion = osVersion
        self.accentColor = accentColor
        self.highlightColor = highlightColor
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
    }

    var fileContents: String {
        """
        osVersion=\(osVersion)
        accentColor=\(accentColor)
        highlightColor=\(highlightColor)
        increaseContrast=\(increaseContrast)
        reduceTransparency=\(reduceTransparency)

        """
    }

    /// Describes the first field in which `self` (the references) and `other` (this Mac) differ.
    func firstDifference(from other: RenderEnvironment) -> String? {
        if osVersion != other.osVersion {
            return "references were recorded on macOS \(osVersion); this Mac runs \(other.osVersion)"
        }
        if accentColor != other.accentColor {
            return "accent color was \(accentColor) when recording; it is \(other.accentColor) here"
        }
        if highlightColor != other.highlightColor {
            return "highlight color was \(highlightColor) when recording; it is \(other.highlightColor) here"
        }
        if increaseContrast != other.increaseContrast {
            return "Increase Contrast was \(increaseContrast ? "on" : "off") when recording; it is \(other.increaseContrast ? "on" : "off") here"
        }
        if reduceTransparency != other.reduceTransparency {
            return "Reduce Transparency was \(reduceTransparency ? "on" : "off") when recording; it is \(other.reduceTransparency ? "on" : "off") here"
        }
        return nil
    }
}

private func kernelOSVersion() -> String? {
    var size = 0
    guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
}

/// A value from the global preferences domain as text, or "default" when it is not set.
private func globalPreference(_ key: String) -> String {
    guard
        let value = CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication)
    else { return "default" }
    return "\(value)"
}

enum SnapshotRunDecision: Equatable, Sendable {
    case run
    case skip(reason: String)
}

func snapshotRunDecision(
    mode: SnapshotMode, recorded: RenderEnvironment?, current: RenderEnvironment
) -> SnapshotRunDecision {
    switch mode {
    case .require:
        return .run
    case .skip:
        return .skip(reason: "UNLATCH_SNAPSHOTS=skip")
    case .auto:
        let hint = "Set UNLATCH_SNAPSHOTS=require to run anyway"
        guard let recorded else {
            return .skip(
                reason: "RECORDED_ON.txt is missing or unreadable, so there is no recorded rendering environment to compare. \(hint)")
        }
        guard let difference = recorded.firstDifference(from: current) else { return .run }
        return .skip(reason: "\(difference). \(hint)")
    }
}

enum SnapshotGate {
    /// Directory that holds the references and `RECORDED_ON.txt`, next to the test files.
    static func snapshotsDirectory(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    static func recordedEnvironmentURL(file: StaticString = #filePath) -> URL {
        snapshotsDirectory(file: file).appendingPathComponent("RECORDED_ON.txt")
    }

    /// Prints the detailed skip reason to stderr when the suite will not run.
    static func shouldRun(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Bool {
        let mode = SnapshotMode(environment: environment)
        let recorded = (try? String(contentsOf: recordedEnvironmentURL(), encoding: .utf8))
            .flatMap(RenderEnvironment.init(fileContents:))
        let current = await MainActor.run { RenderEnvironment.current() }
        switch snapshotRunDecision(mode: mode, recorded: recorded, current: current) {
        case .run:
            return true
        case .skip(let reason):
            FileHandle.standardError.write(Data("Popover snapshot tests skipped: \(reason)\n".utf8))
            return false
        }
    }
}

// MARK: - Test doubles

@MainActor
struct FixedLoginItem: LoginItemService {
    var status: LoginItemStatus
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

extension AppUpdater {
    /// The `swift run` configuration: no Sparkle object is created.
    @MainActor static func snapshotDisabled() -> AppUpdater {
        AppUpdater(availability: .disabled(.notAnAppBundle), shortVersion: nil)
    }
}

// MARK: - Rendering

enum SnapshotAppearance: String, CaseIterable, Sendable {
    case light, dark

    var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
}

/// Renders the production popover content for `model` at a fixed 2x scale on an opaque
/// window-background fill. The bitmap is sized explicitly instead of through the library's
/// `NSView` strategy, which follows the screen's backing scale and so depends on the runner.
@MainActor
func renderPopover(
    _ model: AppModel, updater: AppUpdater, appearance: SnapshotAppearance
) -> NSImage {
    let controller = PopoverHostingController(model: model, updater: updater)
    let view = controller.view
    let nsAppearance = NSAppearance(named: appearance.name)
    view.appearance = nsAppearance
    view.layoutSubtreeIfNeeded()
    let size = controller.preferredContentSize
    view.setFrameSize(size)
    view.layoutSubtreeIfNeeded()

    let scale = 2
    let pixelsWide = Int(size.width.rounded(.up)) * scale
    let pixelsHigh = Int(size.height.rounded(.up)) * scale

    func makeRep() -> NSBitmapImageRep {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { preconditionFailure("Could not allocate a \(pixelsWide) x \(pixelsHigh) bitmap") }
        rep.size = size
        return rep
    }

    let content = makeRep()
    view.cacheDisplay(in: view.bounds, to: content)

    // The popover's own background is NSPopover chrome, out of scope here, so the hosted view
    // is transparent. Composite it over the window background to stand in for that material.
    let composite = makeRep()
    guard let context = NSGraphicsContext(bitmapImageRep: composite) else {
        preconditionFailure("Could not create a graphics context")
    }
    let bounds = NSRect(origin: .zero, size: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // Resolve the dynamic colour under the render's appearance first, then fill with the
    // resolved value.
    var background = NSColor.windowBackgroundColor
    (nsAppearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
        background = NSColor(cgColor: NSColor.windowBackgroundColor.cgColor) ?? background
    }
    context.cgContext.setFillColor(background.cgColor)
    context.cgContext.fill(bounds)
    let contentImage = NSImage(size: size)
    contentImage.addRepresentation(content)
    contentImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: size)
    image.addRepresentation(composite)
    return image
}

// MARK: - Assertion

/// Set once per process, on the main actor, so `RECORDED_ON.txt` is written at most once.
@MainActor private var wroteRecordedOn = false

/// Renders `model` in both appearances and compares each render with its reference
/// (`__Snapshots__/<test file>/popover.<name>-<appearance>.png`).
///
/// Under `swift test` the library emits no failure attachments (those are Xcode-only), so on a
/// mismatch this also writes `<name>.reference.png` and `<name>.difference.png` next to the
/// library's failing render in `SNAPSHOT_ARTIFACTS`.
@MainActor
func assertPopoverSnapshot(
    _ model: AppModel,
    updater: AppUpdater? = nil,
    named name: String,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    let environment = ProcessInfo.processInfo.environment
    let record = recordMode(environment: environment)
    let updater = updater ?? .snapshotDisabled()
    let testName = "popover"
    let testFile = URL(fileURLWithPath: "\(filePath)")
    let fileName = testFile.deletingPathExtension().lastPathComponent
    let referencesDirectory = testFile.deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__").appendingPathComponent(fileName)
    let artifactsDirectory = URL(
        fileURLWithPath: environment["SNAPSHOT_ARTIFACTS"] ?? NSTemporaryDirectory(),
        isDirectory: true
    ).appendingPathComponent(fileName)

    for appearance in SnapshotAppearance.allCases {
        let snapshotName = "\(name)-\(appearance.rawValue)"
        let fileStem = "\(testName).\(snapshotName)"
        let referenceURL = referencesDirectory.appendingPathComponent("\(fileStem).png")
        // Read before verifying: `failed` mode overwrites the reference on a mismatch.
        let referenceData = try? Data(contentsOf: referenceURL)

        let image = renderPopover(model, updater: updater, appearance: appearance)
        let message = verifySnapshot(
            of: image,
            as: .image(
                precision: SnapshotTolerance.precision,
                perceptualPrecision: SnapshotTolerance.perceptualPrecision),
            named: snapshotName,
            record: record,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column)

        guard let message else { continue }
        if let referenceData {
            writeFailureArtifacts(
                reference: referenceData, render: image, directory: artifactsDirectory,
                stem: fileStem)
        }
        Issue.record(
            Comment(rawValue: "\(snapshotName): \(message)"),
            sourceLocation: SourceLocation(
                fileID: "\(fileID)", filePath: "\(filePath)", line: Int(line), column: Int(column)))
    }

    if SnapshotMode(environment: environment) == .require,
        record == .all || record == .failed, !wroteRecordedOn
    {
        wroteRecordedOn = true
        let url = SnapshotGate.recordedEnvironmentURL(file: filePath)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try RenderEnvironment.current().fileContents.write(
                to: url, atomically: true, encoding: .utf8)
        } catch {
            Issue.record("Could not write RECORDED_ON.txt: \(error)")
        }
    }
}

private func writeFailureArtifacts(
    reference: Data, render: NSImage, directory: URL, stem: String
) {
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try reference.write(to: directory.appendingPathComponent("\(stem).reference.png"))
        if let difference = differencePNG(reference: reference, render: render) {
            try difference.write(to: directory.appendingPathComponent("\(stem).difference.png"))
        }
    } catch {
        Issue.record("Could not write snapshot failure artifacts: \(error)")
    }
}

/// A `CIDifferenceBlendMode` blend of the two images: black is identical, lit pixels moved.
private func differencePNG(reference: Data, render: NSImage) -> Data? {
    guard
        let referenceImage = CIImage(data: reference),
        let tiff = render.tiffRepresentation,
        let renderImage = CIImage(data: tiff)
    else { return nil }
    let blended = renderImage.applyingFilter(
        "CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: referenceImage]
    ).cropped(to: renderImage.extent.union(referenceImage.extent))
    let rep = NSBitmapImageRep(ciImage: blended)
    return rep.representation(using: .png, properties: [:])
}
