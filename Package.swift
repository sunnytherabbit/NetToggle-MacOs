// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "NetToggle",
    platforms: [.macOS(.v10_14)],
    targets: [
        .executableTarget(
            name: "NetToggle"
        )
    ],
    swiftLanguageModes: [.v5]
)
