// swift-tools-version: 5.10
import PackageDescription

let ghosttyInclude = "deps/ghostty/include"
let ghosttyLib = "deps/ghostty/zig-out/lib"

let sharedSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-I", ghosttyInclude]),
    // PoC phase: tools-version 5.10 for Swift 5 language mode.
    // Upgrade to 6.0 when strict concurrency is addressed.
]

let package = Package(
    name: "OreoreTerminal",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "GhosttyKit",
            path: "Sources/GhosttyKit"
        ),
        .target(
            name: "OreoreTerminal",
            dependencies: ["GhosttyKit"],
            path: "Sources/OreoreTerminal",
            swiftSettings: sharedSwiftSettings,
            linkerSettings: [
                .unsafeFlags(["-L", ghosttyLib]),
                .linkedLibrary("ghostty"),
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOSurface"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("WebKit"),
            ]
        ),
        .executableTarget(
            name: "OreoreTerminalApp",
            dependencies: ["OreoreTerminal"],
            path: "Sources/OreoreTerminalApp",
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "OreoreTerminalTests",
            dependencies: ["OreoreTerminal"],
            path: "Tests/OreoreTerminalTests",
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
