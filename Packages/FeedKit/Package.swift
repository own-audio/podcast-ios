// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeedKit",
    // macOS only so `swift test` runs on the host without a simulator.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FeedKit", targets: ["FeedKit"])
    ],
    targets: [
        // RSS 2.0 and Atom podcast feeds with the iTunes and Podcasting 2.0 namespaces,
        // Foundation only: `XMLParser` and `URLSession`.
        .target(name: "FeedKit"),
        .testTarget(name: "FeedKitTests", dependencies: ["FeedKit"], resources: [.copy("Fixtures")]),
    ]
)
