// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ImmersiveMapEditor",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ImmersiveMapEditor", targets: ["ImmersiveMapEditor"]),
        .executable(name: "tilepipeline", targets: ["tilepipeline"]),
    ],
    dependencies: [
        // GEOS, the C++ geometry library shapely stands on, built from source.
        .package(url: "https://github.com/GEOSwift/geos.git", exact: "9.0.0"),
    ],
    targets: [
        // GEOS in Swift: what the build does with polygons and lines.
        .target(name: "Geometry", dependencies: [.product(name: "geos", package: "geos")], path: "Sources/Geometry"),
        // glTF binaries read and written.
        .target(name: "GLTF", path: "Sources/GLTF"),
        // The light map's bake on the GPU: Metal ray tracing.
        .target(name: "LightBaker", path: "Sources/LightBaker"),
        // The tile pipeline: OSM to one 3D model per map tile.
        .target(name: "TileKit", dependencies: ["Geometry", "GLTF", "LightBaker"], path: "Sources/TileKit"),
        .executableTarget(name: "ImmersiveMapEditor", dependencies: ["TileKit", "Geometry"], path: "Sources/ImmersiveMapEditor"),
        .testTarget(name: "TileKitTests", dependencies: ["TileKit", "Geometry"], path: "Tests/TileKitTests"),
        .testTarget(name: "ImmersiveMapEditorTests", dependencies: ["ImmersiveMapEditor", "Geometry"], path: "Tests/ImmersiveMapEditorTests"),
        .executableTarget(name: "tilepipeline", dependencies: ["TileKit", "Geometry", "GLTF"], path: "Sources/tilepipeline"),
    ],
    swiftLanguageModes: [.v5]
)
