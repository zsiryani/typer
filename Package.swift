// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "typer",
    platforms: [
        .macOS(.v13) // macOS Ventura or later (required for MenuBarExtra)
    ],
    products: [
        .executable(
            name: "typer",
            targets: ["typer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "typer",
            path: "typer", // Points directly to your typer/ subfolder
            resources: [
                .process("Assets.xcassets") // Bundles AppIcon and AccentColor
            ]
        )
    ]
)
