// swift-tools-version:6.0
// BioLab — native macOS developer toolkit (SwiftUI rewrite of apps/desktop).

import PackageDescription

let package = Package(
    name: "BioLab",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Format-preserving-enough TOML editing for Codex's config.toml.
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "BioLab",
            dependencies: ["TOMLKit"],
            path: "Sources/BioLab",
            resources: [.copy("Resources/tray.png"), .copy("Resources/Brands")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
