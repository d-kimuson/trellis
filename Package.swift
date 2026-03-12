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
    name: "Trellis",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "GhosttyKit",
            path: "Sources/GhosttyKit"
        ),
        .target(
            name: "Trellis",
            dependencies: ["GhosttyKit"],
            path: "Sources/Trellis",
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
                .linkedFramework("CoreVideo"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("WebKit"),
            ]
        ),
        .executableTarget(
            name: "TrellisApp",
            dependencies: ["Trellis"],
            path: "Sources/TrellisApp",
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "TrellisTests",
            dependencies: ["Trellis"],
            path: "Tests/TrellisTests",
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
