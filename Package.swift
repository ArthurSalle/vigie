// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vigie",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Vigie",
            path: "Sources/Vigie",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
