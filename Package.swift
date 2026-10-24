// swift-tools-version: 6.0
import PackageDescription

let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "PS3Center",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ps3", targets: ["ps3"]),
        .library(name: "PS3Kit", targets: ["PS3Kit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "PS3Kit", swiftSettings: settings),
        .executableTarget(
            name: "ps3",
            dependencies: [
                "PS3Kit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: settings
        ),
        .testTarget(name: "PS3KitTests", dependencies: ["PS3Kit"], swiftSettings: settings),
    ]
)
