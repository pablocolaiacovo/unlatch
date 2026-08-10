// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UnlatchCore",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "UnlatchCore",
            targets: ["UnlatchCore"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "UnlatchCore"
        ),
        .testTarget(
            name: "UnlatchCoreTests",
            dependencies: ["UnlatchCore"],
            // .copy, not .process: the fixtures must keep their directory
            // structure for Bundle.module lookups with subdirectory: "Fixtures".
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
