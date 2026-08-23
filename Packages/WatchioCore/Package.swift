// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WatchioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WatchioModels", targets: ["WatchioModels"]),
        .library(name: "WatchioDetection", targets: ["WatchioDetection"]),
        .library(name: "WatchioStorage", targets: ["WatchioStorage"]),
    ],
    targets: [
        .target(name: "WatchioModels"),
        .target(name: "WatchioDetection", dependencies: ["WatchioModels"]),
        .target(name: "WatchioStorage", dependencies: ["WatchioModels"]),
        .testTarget(name: "WatchioModelsTests", dependencies: ["WatchioModels"]),
        .testTarget(name: "WatchioDetectionTests", dependencies: ["WatchioDetection", "WatchioModels"]),
        .testTarget(name: "WatchioStorageTests", dependencies: ["WatchioStorage", "WatchioModels"]),
    ],
    swiftLanguageModes: [.v6]
)
