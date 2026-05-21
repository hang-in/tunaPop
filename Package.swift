// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TunaPop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TunaPop", targets: ["TunaPop"])
    ],
    targets: [
        .executableTarget(
            name: "TunaPop",
            path: "Sources/TunaPop"
        )
    ]
)
