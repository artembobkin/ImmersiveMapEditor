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
        // The engine itself, at its main branch (the user, 2026-11-05). Two
        // of its products are linked: `ImmersiveMap`, whose map the Engine
        // view shows the model archive on (the user, 2026-11-02), and
        // `ModelTileFormat`, the model tile as bytes, and `PMTiles`, for its
        // writer, which TileKit writes the archive and its tiles with, so
        // the formats are in one place for the engine and the editor (the
        // user, 2026-11-16).
        .package(url: "https://github.com/artembobkin/ImmersiveMap.git", branch: "main"),
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
        // The tile pipeline: OSM to one 3D model per map tile.
        .target(name: "TileKit", dependencies: ["Geometry", "GLTF", .product(name: "Manifold", package: "SwiftManifold"), .product(name: "Streets", package: "SwiftStreets"),
                                              .product(name: "StreetGeom", package: "SwiftStreets"),
                                              .product(name: "ModelTileFormat", package: "ImmersiveMap"), .product(name: "PMTiles", package: "ImmersiveMap")],
                path: "Sources/TileKit"),
        .executableTarget(name: "ImmersiveMapEditor", dependencies: ["TileKit", "Geometry", .product(name: "ImmersiveMap", package: "ImmersiveMap")], path: "Sources/ImmersiveMapEditor"),
        .testTarget(name: "TileKitTests", dependencies: ["TileKit", "Geometry"], path: "Tests/TileKitTests"),
        .testTarget(name: "ImmersiveMapEditorTests", dependencies: ["ImmersiveMapEditor", "Geometry"], path: "Tests/ImmersiveMapEditorTests"),
    ],
    swiftLanguageModes: [.v5]
)
