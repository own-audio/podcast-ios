// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GPodderKit",
    // macOS only so `swift test` runs on the host without a simulator.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "GPodderKit", targets: ["GPodderKit"])
    ],
    targets: [
        // A client for the gPodder API (gpodder.net's v2, as podfetch, Nextcloud's gPodder
        // Sync and others serve it), Foundation only.
        .target(name: "GPodderKit"),
        .testTarget(name: "GPodderKitTests", dependencies: ["GPodderKit"]),
    ]
)
