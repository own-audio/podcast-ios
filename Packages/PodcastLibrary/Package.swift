// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodcastLibrary",
    // macOS only so `swift test` runs on the host without a simulator.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PodcastLibrary", targets: ["PodcastLibrary"])
    ],
    dependencies: [
        .package(path: "../FeedKit"),
        .package(path: "../AudiobookshelfKit"),
    ],
    targets: [
        // The app's model of shows and episodes, the sources behind it, and the logic of the
        // inbox and the queue. No UI.
        .target(name: "PodcastLibrary", dependencies: ["FeedKit", "AudiobookshelfKit"]),
        .testTarget(name: "PodcastLibraryTests", dependencies: ["PodcastLibrary"]),
    ]
)
