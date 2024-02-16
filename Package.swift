// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocoKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "LocoKit", targets: ["LocoKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/alejandro-isaza/Upsurge.git", from: "0.11.0"),
        .package(name: "GRDB", url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(name: "FlatBuffers", url: "https://github.com/mustiikhalil/flatbuffers", from: "0.8.1")
    ],
    targets: [
        .target(
            name: "LocoKit",
            dependencies: ["Upsurge", "GRDB", "FlatBuffers"], 
            path: "LocoKit",
            exclude: ["Base/Strings", "Timelines/ActivityTypes/CoordinateBins.fbs"]
        )
    ]
)
