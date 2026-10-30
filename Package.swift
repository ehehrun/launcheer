// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Launcheer",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .target(
            name: "NativeLaunchpad",
            path: "Sources/NativeLaunchpad",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc", "-Werror", "-Wall", "-Wextra", "-Wno-unused-parameter"])],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("QuartzCore"), .linkedFramework("ImageIO")]
        ),
        .executableTarget(
            name: "Launcheer",
            dependencies: ["NativeLaunchpad"],
            path: "Sources/Launcheer"
        ),
        .testTarget(
            name: "LauncheerTests",
            dependencies: ["Launcheer", "NativeLaunchpad"]
        )
    ]
)
