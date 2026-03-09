// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-codex-examples",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "basic-example",
            targets: ["BasicExample"]
        ),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "BasicExample",
            dependencies: [
                .product(name: "Codex", package: "swift-codex"),
            ]
        ),
    ]
)
