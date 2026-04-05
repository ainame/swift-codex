// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-codex",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Codex",
            targets: ["Codex"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.6.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.1.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Codex",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .testTarget(
            name: "CodexTests",
            dependencies: [
                "Codex",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
