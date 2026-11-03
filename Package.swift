// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ImmersiveMapEditor",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ImmersiveMapEditor", targets: ["ImmersiveMapEditor"]),
    ],
    dependencies: [
        // The ports, each its own repository: JTS 1.20.0 behaving as GEOS 3.13,
        // and osm2streets (rev fc119c4) with what it stands on.
        .package(url: "https://github.com/artembobkin/SwiftTopology.git", exact: "0.1.0"),
        .package(url: "https://github.com/artembobkin/SwiftStreets.git", exact: "0.1.1"),
        // Manifold (github.com/elalish/manifold) in Swift, bit for bit with the
        // C++: the union of a landmark's solids into one shell.
        .package(url: "https://github.com/artembobkin/SwiftManifold.git", exact: "0.1.0"),
        // The engine itself, read and never changed from here, at its last
        // release: the Engine view shows the model archive on its map (the
        // user, 2026-11-02). A new release is a new exact version here.
        .package(url: "https://github.com/artembobkin/ImmersiveMap.git", exact: "0.11.1"),
    ],
    targets: [
        // What the build does with polygons and lines, shapely's names on Topology.
        .target(name: "Geometry", dependencies: [.product(name: "Topology", package: "SwiftTopology")], path: "Sources/Geometry"),
        // The wrapper against GEOS 3.13's answers, stored when GEOS left (Docs/PortingParity.md).
        .testTarget(name: "GeometryTests", dependencies: ["Geometry", .product(name: "Topology", package: "SwiftTopology")],
                    path: "Tests/GeometryTests"),
        // glTF binaries read and written.
        .target(name: "GLTF", path: "Sources/GLTF"),
        // The light map's bake on the GPU: Metal ray tracing.
        .target(name: "LightBaker", path: "Sources/LightBaker"),
        // The tile pipeline: OSM to one 3D model per map tile.
        .target(name: "TileKit", dependencies: ["Geometry", "GLTF", "LightBaker", .product(name: "Manifold", package: "SwiftManifold"), .product(name: "Streets", package: "SwiftStreets"),
                                              .product(name: "StreetGeom", package: "SwiftStreets")], path: "Sources/TileKit"),
        .executableTarget(name: "ImmersiveMapEditor", dependencies: ["TileKit", "Geometry", .product(name: "ImmersiveMap", package: "ImmersiveMap")], path: "Sources/ImmersiveMapEditor"),
        .testTarget(name: "TileKitTests", dependencies: ["TileKit", "Geometry"], path: "Tests/TileKitTests"),
        .testTarget(name: "ImmersiveMapEditorTests", dependencies: ["ImmersiveMapEditor", "Geometry"], path: "Tests/ImmersiveMapEditorTests"),
    ],
    swiftLanguageModes: [.v5]
)
