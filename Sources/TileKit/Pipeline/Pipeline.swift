import Foundation

/// The production pipeline: map tiles of Moscow, each into one 3D model the
/// engine shows over its vector tile. For every tile, in order:
///
/// 1. fetch: OSM of the tile and a margin (Fetch), unless already on disk;
/// 2. roads: the road documents of the tiles (roads/). The tiles no document
///    holds yet are cut into ranges and each range seeded from osm2streets
///    and OSM (Seed). A seeded document is never seeded again here: it holds
///    the hand edits of the editor;
/// 3. build: the whole tile (Build): the roads of the document, buildings,
///    landmarks, construction sites, bus shelters, the light map, cut to the
///    tile's edges, written as GLB, placement.json and metadata.json, and the
///    scene of its light in bake/, so `pipeline bake` can bake it again;
/// 4. validate: Validate, against the rules of TilePipeline's CLAUDE.md.
///
/// Writes out/tiles/<z>/<x>/<y>/ per tile and out/tiles/index.json, the list
/// of tiles with their state. A tile that fails stops nothing: the others
/// are built and the failure is recorded.
public enum Pipeline {
    public struct Options {
        public var refetch = false
        public var samples = 256
        /// Whether the light is baked with the build: without it the light
        /// map is white, until `pipeline bake`.
        public var bakeLight = true
        public init() {}
    }

    /// A set of tiles cut into ranges, greedily: from the first tile left in
    /// row order, as far east as the set goes, then as far south as whole
    /// rows of that width go.
    public static func rectangles(_ tiles: Set<[Int]>) -> [(Int, Int, Int, Int)] {
        var left = tiles
        var made: [(Int, Int, Int, Int)] = []
        while let first = left.min(by: { ($0[1], $0[0]) < ($1[1], $1[0]) }) {
            let (x0, y0) = (first[0], first[1])
            var x1 = x0
            while left.contains([x1 + 1, y0]) { x1 += 1 }
            var y1 = y0
            while (x0...x1).allSatisfy({ left.contains([$0, y1 + 1]) }) { y1 += 1 }
            made.append((x0, y0, x1, y1))
            for x in x0...x1 { for y in y0...y1 { left.remove([x, y]) } }
        }
        return made
    }

    /// Seeds the road documents of the tiles that have none yet. Returns the
    /// tiles seeded.
    public static func ensureRoads(_ paths: WorkspacePaths, z: Int, tiles: [(Int, Int)]) throws -> [String] {
        var seeded: [String] = []
        for (x, y) in tiles where RoadDocument.find(z: z, x: x, y: y, in: paths) == nil {
            // Only a tile with no road document: one there is never seeded again.
            Progress.report("Seeding the roads of \(z)/\(x)/\(y): it has no road document")
            _ = try Seed.run(paths, z: z, x: x, y: y)
            seeded.append("\(z)/\(x)/\(y)")
        }
        return seeded
    }

    public static func run(_ paths: WorkspacePaths, z: Int, tiles: [(Int, Int)], options: Options = Options()) throws -> Bool {
        let out = paths.tiles
        for (x, y) in tiles {
            let data = paths.tileData(z: z, x: x, y: y)
            if options.refetch || !FileManager.default.fileExists(atPath: data.appendingPathComponent("osm.json").path) {
                try Fetch.tile(paths, z: z, x: x, y: y, force: options.refetch)
            }
        }
        let seeded = try ensureRoads(paths, z: z, tiles: tiles)
        if !seeded.isEmpty { print("roads seeded for " + seeded.joined(separator: ", ")) }
        let indexURL = out.appendingPathComponent("index.json")
        var index: [String: [String: Any]] = [:]
        if let data = try? Data(contentsOf: indexURL),
           let old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for t in old["tiles"] as? [[String: Any]] ?? [] { index[t["tile"] as? String ?? ""] = t }
        }
        for (x, y) in tiles {
            let name = "\(z)/\(x)/\(y)"
            print(name)
            let folder = paths.tileOut(z: z, x: x, y: y)
            var state: [String: Any] = ["tile": name, "folder": "tiles/\(z)/\(x)/\(y)/build"]
            let started = Date()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // A stale GLB would pass validation after a failed build, and a
                // stale bake/ would bake the old geometry.
                for stale in ["placement.json", "metadata.json", "validation.json", "stats.json", "tile_\(z)_\(x)_\(y).glb", Bake.folder] {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(stale))
                }
                let tile = try Tile(folder: paths.tileData(z: z, x: x, y: y))
                let t0 = Date()
                var light = Lighting.Settings()
                light.samples = options.samples
                try Build.run(paths, tile: tile, out: folder, whole: true, export: true, light: light, bakeLight: options.bakeLight)
                state["build_s"] = round(Date().timeIntervalSince(t0) * 10) / 10
                print(String(format: "  build     ok in %.1f s", state["build_s"] as! Double))
                Progress.report("Validating")
                let result = try Validate.tile(folder)
                print("  validate  \(result.ok ? "ok" : "FAILED")")
                for c in result.checks where !c.ok { print("    FAIL \(c.name) \(c.detail)") }
                state["state"] = result.ok ? "ok" : "failed at validate"
                state["triangles"] = result.triangles
                state["glb_mb"] = round(Double(result.bytes) / 1e5) / 10
            } catch {
                print("  FAILED: \(error)")
                state["state"] = "failed: \(error)"
            }
            state["seconds"] = round(Date().timeIntervalSince(started) * 10) / 10
            index[name] = state
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let list = index.values.sorted { ($0["tile"] as? String ?? "") < ($1["tile"] as? String ?? "") }
            try JSONSerialization.data(withJSONObject: ["tiles": list], options: [.prettyPrinted, .sortedKeys]).write(to: indexURL)
        }
        let failed = index.values.filter { ($0["state"] as? String) != "ok" }.count
        print("\(index.count - failed) tiles ok, \(failed) failed")
        return failed == 0
    }
}
