// swift-tools-version: 6.0
import PackageDescription

let settings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "PS3Center",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ps3", targets: ["ps3"]),
        .library(name: "PS3Kit", targets: ["PS3Kit"]),
        .library(name: "PS3KitFixtures", targets: ["PS3KitFixtures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "PS3Kit", swiftSettings: settings),
        // Canned console data for the app's screenshots and the tests; not part of the CLI.
        .target(name: "PS3KitFixtures", dependencies: ["PS3Kit"], swiftSettings: settings),
        .executableTarget(
            name: "ps3",
            dependencies: [
                "PS3Kit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: settings
        ),
        .testTarget(name: "PS3KitTests", dependencies: ["PS3Kit", "PS3KitFixtures"], swiftSettings: settings),
        // Every subcommand's options parse: ArgumentParser only checks them when one runs.
        .testTarget(name: "ps3Tests", dependencies: ["ps3"], swiftSettings: settings),
    ]
)
