// swift-tools-version: 6.0
// BQCore: everything Bezpečné QR knows about codes, without UI or networking.
// Classifier, parsers, validators, rules and the risk engine. `swift test` runs on the Mac.
import PackageDescription

let package = Package(
    name: "BQCore",
    defaultLocalization: "cs",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BQCore", targets: ["BQCore"]),
    ],
    targets: [
        .target(
            name: "BQCore",
            resources: [
                // Copied from shared/ by scripts/sync-core-resources.sh (a test checks they match).
                .copy("Resources/rules"),
                .copy("Resources/content"),
            ]
        ),
        .testTarget(name: "BQCoreTests", dependencies: ["BQCore"]),
    ]
)
