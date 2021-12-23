// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocoKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "LocoKit", targets: ["LocoKit"])
    ],
    dependencies: [
//        .package(url: "https://github.com/alejandro-isaza/Upsurge.git", from: "0.11.0"),
        .package(name: "GRDB", url: "https://github.com/groue/GRDB.swift.git", from: "5.0.0"),
        .package(name: "FlatBuffers", url: "https://github.com/mustiikhalil/flatbuffers", from: "0.8.1")
    ],
    targets: [
        .target(
            name: "LocoKit",
            dependencies: ["GRDB", "FlatBuffers"], 
            path: "LocoKit",
            exclude: ["Base/Strings", "Timelines/ActivityTypes/CoordinateBins.fbs"]
        )
    ]
)
