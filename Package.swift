// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeGamepad",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeGamepad",
            path: "Sources/ClaudeGamepad",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("GameController"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
