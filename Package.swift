// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocoKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "LocoKit", targets: ["LocoKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/alejandro-isaza/Upsurge.git", from: "0.11.0"),
        .package(name: "GRDB", url: "https://github.com/groue/GRDB.swift.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "LocoKit",
            dependencies: ["Upsurge", "GRDB"], 
            path: "LocoKit",
            resources: [.process("Base/Strings")]
        )
    ]
)
