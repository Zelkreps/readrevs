// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ReadRevs",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "ReadRevs",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Config/Info.plist",
                ]),
            ]
        ),
        .testTarget(name: "ReadRevsTests", dependencies: ["ReadRevs"]),
    ]
)
