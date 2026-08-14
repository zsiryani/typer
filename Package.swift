// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "typer",
    platforms: [
        .macOS(.v13) // Required for SwiftUI MenuBarExtra
    ],
    products: [
        .executable(
            name: "typer",
            targets: ["typer"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "typer",
            dependencies: [],
            path: "Sources" // Points to your source files directory
        )
    ]
)
