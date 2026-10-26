// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ImmersiveMapEditor",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ImmersiveMapEditor", targets: ["ImmersiveMapEditor"]),
    ],
    dependencies: [
        // The ports, each its own repository: JTS 1.20.0 behaving as GEOS 3.13,
        // and osm2streets (rev fc119c4) with what it stands on.
        .package(url: "https://github.com/artembobkin/SwiftTopology.git", exact: "0.1.0"),
        .package(url: "https://github.com/artembobkin/SwiftStreets.git", exact: "0.1.0"),
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
        // Manifold (github.com/elalish/manifold, Apache 2.0, its sources in manifold/), behind a small C face:
        // the union of a landmark's solids into one mesh.
        .target(name: "CManifold", path: "Sources/CManifold", exclude: ["manifold/LICENSE", "manifold/REVISION"],
                cxxSettings: [.headerSearchPath("manifold/include"), .define("MANIFOLD_PAR", to: "-1")]),
        // The tile pipeline: OSM to one 3D model per map tile.
        .target(name: "TileKit", dependencies: ["Geometry", "GLTF", "LightBaker", "CManifold", .product(name: "Streets", package: "SwiftStreets"),
                                              .product(name: "StreetGeom", package: "SwiftStreets")], path: "Sources/TileKit"),
        .executableTarget(name: "ImmersiveMapEditor", dependencies: ["TileKit", "Geometry"], path: "Sources/ImmersiveMapEditor"),
        .testTarget(name: "TileKitTests", dependencies: ["TileKit", "Geometry"], path: "Tests/TileKitTests"),
        .testTarget(name: "ImmersiveMapEditorTests", dependencies: ["ImmersiveMapEditor", "Geometry"], path: "Tests/ImmersiveMapEditorTests"),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
