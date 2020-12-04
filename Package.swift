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
        .target(
            name: "LocoKit",
            dependencies: [
                .package(url: "https://github.com/alejandro-isaza/Upsurge", from: "0.11.0"),
                .package(url: "https://github.com/groue/GRDB.swift", from: "4.0.0")
            ], 
            path: "LocoKit"
        )
    ]
)
