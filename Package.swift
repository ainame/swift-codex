// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-codex",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "Codex",
            targets: ["Codex"]
        ),
        .library(
            name: "CodexBridgeClient",
            targets: ["CodexBridgeClient"]
        ),
        .executable(
            name: "CodexBridge",
            targets: ["CodexBridge"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.6.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.1.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "CodexCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "Codex",
            dependencies: [
                "CodexCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SystemPackage", package: "swift-system", condition: .when(platforms: [.macOS])),
                .product(name: "Subprocess", package: "swift-subprocess", condition: .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "CodexBridgeClient",
            dependencies: [
                "CodexCore",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "CodexBridge",
            dependencies: [
                "Codex",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .testTarget(
            name: "CodexTests",
            dependencies: [
                "Codex",
                "CodexBridgeClient",
                "CodexCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
