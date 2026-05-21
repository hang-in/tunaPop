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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "TunaPop",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/TunaPop",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
