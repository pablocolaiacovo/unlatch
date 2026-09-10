// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UnlatchCore",
    // PDFKit is Apple-only, so declare the platform rather than let consumers
    // discover it as an import failure. The menu bar app uses MenuBarExtra
    // window style plus @Observable, which need macOS 14.
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
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "UnlatchCore"
        ),
        .executableTarget(
            name: "Unlatch",
            dependencies: ["UnlatchCore"]
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
