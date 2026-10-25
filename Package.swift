// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ImmersiveMapEditor",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ImmersiveMapEditor", targets: ["ImmersiveMapEditor"]),
        .executable(name: "tilepipeline", targets: ["TilePipelineCommand"]),
    ],
    targets: [
        // What the build does with polygons and lines, shapely's names on Topology.
        .target(name: "Geometry", dependencies: ["Topology"], path: "Sources/Geometry"),

        // The ports (Docs/PortingGoal.md). Topology: the JTS Topology Suite
        // 1.20.0 in Swift (EDL-1.0), the engine under Geometry (behaving as GEOS 3.13).
        .target(name: "Topology", path: "Sources/Topology", exclude: ["LICENSE", "LICENSE-LLVM"]),
        // osm2streets (rev fc119c4) and what it stands on, each its own target.
        .target(name: "Earcut", path: "Sources/Earcut", exclude: ["LICENSE"]),
        .target(name: "GeoAlgorithms", path: "Sources/GeoAlgorithms", exclude: ["LICENSE"]),
        .target(name: "StreetGeom", dependencies: ["GeoAlgorithms", "Earcut"], path: "Sources/StreetGeom", exclude: ["NOTICE"]),
        .target(name: "OSMReader", path: "Sources/OSMReader", exclude: ["NOTICE"]),
        .target(name: "CountryBoundaries", path: "Sources/CountryBoundaries", exclude: ["NOTICE"]),
        // Muv's reading of lanes from OSM tags (muv-osm, rev 2404d40), the one
        // MPL-2.0 target: its files stay under the MPL, the rest of the package MIT.
        .target(name: "MuvLanes", path: "Sources/MuvLanes", exclude: ["LICENSE"]),
        .target(name: "Streets", dependencies: ["StreetGeom", "GeoAlgorithms", "OSMReader", "CountryBoundaries", "MuvLanes"],
                path: "Sources/Streets", exclude: ["NOTICE"]),
        // The port against GEOS 3.13's answers, stored when GEOS left (Docs/PortingParity.md).
        .testTarget(name: "TopologyTests", dependencies: ["Topology", "Geometry"], path: "Tests/TopologyTests"),
        .testTarget(name: "StreetsTests", dependencies: ["Streets", "StreetGeom", "GeoAlgorithms", "Earcut", "OSMReader",
                                                         "CountryBoundaries", "MuvLanes"], path: "Tests/StreetsTests"),
        // glTF binaries read and written.
        .target(name: "GLTF", path: "Sources/GLTF"),
        // The light map's bake on the GPU: Metal ray tracing.
        .target(name: "LightBaker", path: "Sources/LightBaker"),
        // The tile pipeline: OSM to one 3D model per map tile.
        .target(name: "TileKit", dependencies: ["Geometry", "GLTF", "LightBaker", "Streets"], path: "Sources/TileKit"),
        .executableTarget(name: "ImmersiveMapEditor", dependencies: ["TileKit", "Geometry"], path: "Sources/ImmersiveMapEditor"),
        .testTarget(name: "TileKitTests", dependencies: ["TileKit", "Geometry"], path: "Tests/TileKitTests"),
        .testTarget(name: "ImmersiveMapEditorTests", dependencies: ["ImmersiveMapEditor", "Geometry"], path: "Tests/ImmersiveMapEditorTests"),
        // The command line over TileKit; the program is `tilepipeline`.
        .executableTarget(name: "TilePipelineCommand", dependencies: ["TileKit", "Geometry", "GLTF"], path: "Sources/TilePipelineCommand"),
    ],
    swiftLanguageModes: [.v5]
)
