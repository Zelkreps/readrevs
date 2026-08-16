// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ReadRevs",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReadRevsCore", targets: ["ReadRevsCore"]),
        .executable(name: "ReadRevsApp", targets: ["ReadRevsApp"]),
    ],
    targets: [
        .target(name: "ReadRevsCore"),
        .executableTarget(
            name: "ReadRevsApp",
            dependencies: ["ReadRevsCore"]
        ),
        .testTarget(
            name: "ReadRevsCoreTests",
            dependencies: ["ReadRevsCore"]
        ),
        .testTarget(
            name: "ReadRevsAppTests",
            dependencies: ["ReadRevsApp", "ReadRevsCore"]
        ),
    ]
)
