// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ImmersiveMapEditor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ImmersiveMapEditor", path: "Sources/ImmersiveMapEditor"),
    ]
)
