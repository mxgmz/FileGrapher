// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GraphingApp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GraphingApp",
            path: "Sources/GraphingApp"
        )
    ],
    swiftLanguageModes: [.v5]
)
