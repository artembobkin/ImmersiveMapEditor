import Foundation
import GLTF

/// The tile's model as the engine's tooling takes it (TilePipeline's
/// CLAUDE.md, "The model file: GLB"): one GLB, a placement.json in the form
/// Modeling uses, and a metadata JSON with the tile, the sources and the
/// statistics.
///
/// The GLB holds the one mesh, triangles only, indexed, with POSITION,
/// NORMAL (each face's own) and TEXCOORD_0 (the palette), and one material:
/// the palette as its base colour texture, embedded as PNG. Nothing else:
/// no light map and no second UV (the user, 2026-11-16: the tiles carry no
/// light, their palette's colours plain). +Z up turns into +Y up, north into -Z, and the UVs' V
/// turns to run down, as glTF has it.
public enum Export {
    static let attribution = "© OpenStreetMap contributors, ODbL"

    /// The zoom of the map tiles whose buildings a model replaces: the
    /// basemap's deepest, the engine's `ImmersiveMapTilesService.maximumTileZoomLevel`.
    public static let replacedZoom = 15

    /// Writes <name>.glb, placement.json and metadata.json into `out` from
    /// the cut triangles. Returns the GLB's URL.
    @discardableResult
    public static func tile(_ m: Triangles, uv0: [Double], palette: PaletteTexture, tile: Tile, out: URL, stats: [String: Any], models: [String]) throws -> URL {
        let name = "tile_\(tile.z)_\(tile.x)_\(tile.y)"
        let url = out.appendingPathComponent("\(name).glb")
        // Corners alike in every attribute are one vertex.
        var positions: [Float] = [], normals: [Float] = [], uv0s: [Float] = [], indices: [UInt32] = []
        var seen: [[Float]: UInt32] = [:]
        func key(_ v: Double) -> Float { Float((v * 1e5).rounded() / 1e5) }
        for t in 0..<m.count {
            let n = m.normal(t).normalized
            for i in 0..<3 {
                let c = m.corner(t, i)
                // (x, y, z) to (x, z, -y), V down.
                let j = t * 6 + i * 2
                let u0: Float = key(uv0[j]), v0: Float = key(1.0 - uv0[j + 1])
                var row: [Float] = [key(c.x), key(c.z), key(-c.y)]
                row += [key(n.x), key(n.z), key(-n.y)]
                row += [u0, v0]
                if let k = seen[row] {
                    indices.append(k)
                    continue
                }
                let k = UInt32(seen.count)
                seen[row] = k
                indices.append(k)
                positions += row[0..<3]
                normals += row[3..<6]
                uv0s += row[6..<8]
            }
        }
        try GLTF.write(url, positions: positions, normals: normals, uv0: uv0s, indices: indices,
                       basePNG: PNG.encode(palette.pixels, width: palette.size, height: palette.size, channels: 3), name: "tile")
        var placement: [String: Any] = [
            "id": name.replacingOccurrences(of: "_", with: "-"), "model": "\(name).glb",
            "origin": ["latitude": tile.centreLatitude, "longitude": tile.centreLongitude], "altitude_m": 0,
        ]
        // The map's own buildings the model stands in for, listed for the
        // map tiles' deepest zoom, where a feature is one building (the
        // tiles above merge them, so nothing can be left out there).
        if let replaced = stats["replaced_buildings"] as? [String], !replaced.isEmpty {
            placement["replaces"] = ["\(replacedZoom)": replaced]
        }
        try write(placement, out.appendingPathComponent("placement.json"))
        let osm = tile.info["osm"] as? [String: Any] ?? [:]
        let built = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        let meta: [String: Any] = [
            "tile": ["z": tile.z, "x": tile.x, "y": tile.y],
            "centre": tile.info["centre"] ?? [:],
            "size_m": tile.size,
            "units_per_metre": tile.unitsPerMetre,
            "built": built,
            "sources": [
                "osm": ["source", "fetched", "timestamp", "query", "extract"].reduce(into: [String: Any]()) { $0[$1] = osm[$1] ?? NSNull() },
                "osm2streets": ["revision": RoadDocument.osm2streetsRevision],
                "landmarks": models.sorted(),
                "landmarks_pending": stats["landmarks_pending"] ?? [String: Int](),
            ],
            "statistics": stats,
            "attribution": attribution,
        ]
        try write(meta, out.appendingPathComponent("metadata.json"))
        return url
    }

    static func write(_ object: Any, _ url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: url)
    }
}
