// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UnlatchCore",
    // PDFKit is Apple-only, so declare the platform rather than let consumers
    // discover it as an import failure. The menu bar app's macOS 14 floor is
    // for @Observable and NSApp.activate(ignoringOtherApps:), not for
    // MenuBarExtra — the popover is hosted via NSStatusItem + NSPopover.
    platforms: [.macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "UnlatchCore",
            targets: ["UnlatchCore"]
        ),
        .executable(
            name: "Unlatch",
            targets: ["Unlatch"]
        ),
    ],
    dependencies: [
        // Exact pin: Scripts/package-app.sh relies on this release's bundle layout
        // (Versions/B, Autoupdate, Updater.app, XPCServices). Bump deliberately,
        // in its own PR, and re-run the release workflow's dry run.
        // 2.9.2 or later is mandatory: CVE-2026-47122 affects <= 2.9.1.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "UnlatchCore"
        ),
        .executableTarget(
            name: "Unlatch",
            dependencies: ["UnlatchCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Inside Unlatch.app the framework lives in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                // No @loader_path entry here: for `swift run Unlatch` and the test
                // runner (framework next to the binary in .build/<config>/), SwiftPM
                // on Xcode 27 / Swift 6.4 already adds `@loader_path` to every
                // executable. Adding it again only produces a "duplicate -rpath" linker warning. If a future
                // toolchain drops it, `swift run Unlatch` fails with "Library not
                // loaded"; re-add it then.
            ]
        ),
        .testTarget(
            name: "UnlatchCoreTests",
            dependencies: ["UnlatchCore"],
            // .copy, not .process: the fixtures must keep their directory
            // structure for Bundle.module lookups with subdirectory: "Fixtures".
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "UnlatchTests",
            dependencies: ["Unlatch"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
