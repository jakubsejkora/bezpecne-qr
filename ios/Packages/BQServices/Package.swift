// swift-tools-version: 6.0
// BQServices: the network side of Bezpečné QR — the link inspector (SafeFetcher, page extract),
// Quad9 DoH and RDAP. Extension-safe, no third-party dependencies. `swift test` runs on the Mac.
import PackageDescription

let package = Package(
    name: "BQServices",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BQServices", targets: ["BQServices"]),
    ],
    dependencies: [
        .package(path: "../BQCore"),
    ],
    targets: [
        .target(
            name: "BQServices",
            dependencies: [.product(name: "BQCore", package: "BQCore")],
            resources: [
                // IANA RDAP bootstrap snapshot (see README for the retrieval date).
                .copy("Resources/rdap-dns.json"),
            ]
        ),
        .testTarget(
            name: "BQServicesTests",
            dependencies: ["BQServices", .product(name: "BQCore", package: "BQCore")]
        ),
    ]
)
