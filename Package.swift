// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocoKit",
    products: [
        .library(name: "LocoKit", targets: ["LocoKit"])
    ],
    dependencies: [],
    targets: [
        .target(name: "LocoKit", dependencies: [], path: "LocoKit")
        .binaryTarget(name: "LocoKitCore", path: "LocoKitCore.framework.zip")
    ]
)
