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
///    tile's edges, written as GLB, placement.json and metadata.json;
/// 4. validate: Validate, against the rules of TilePipeline's CLAUDE.md.
///
/// Writes out/tiles/<z>/<x>/<y>/ per tile and out/tiles/index.json, the list
/// of tiles with their state. A tile that fails stops nothing: the others
/// are built and the failure is recorded.
public enum Pipeline {
    public struct Options {
        public var refetch = false
        public var samples = 256
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

    /// Seeds road documents for the tiles no document holds yet. Returns
    /// the documents the tiles take their roads from.
    public static func ensureRoads(z: Int, tiles: [(Int, Int)]) throws -> [String] {
        var names = Set<String>(), missing = Set<[Int]>()
        for (x, y) in tiles {
            if let url = RoadDocument.find(z: z, x: x, y: y) { names.insert(url.lastPathComponent) } else { missing.insert([x, y]) }
        }
        for (x0, y0, x1, y1) in rectangles(missing) {
            names.insert(try Seed.run(z: z, x0: x0, y0: y0, x1: x1, y1: y1).lastPathComponent)
        }
        return names.sorted()
    }

    public static func run(z: Int, tiles: [(Int, Int)], options: Options = Options()) throws -> Bool {
        let out = pipelineRoot.appendingPathComponent("out/tiles")
        for (x, y) in tiles {
            let data = Fetch.folder(z: z, x: x, y: y)
            if options.refetch || !FileManager.default.fileExists(atPath: data.appendingPathComponent("osm.json").path) {
                try Fetch.tile(z: z, x: x, y: y, force: options.refetch)
            }
        }
        print("roads from roads/" + (try ensureRoads(z: z, tiles: tiles)).joined(separator: ", roads/"))
        let indexURL = out.appendingPathComponent("index.json")
        var index: [String: [String: Any]] = [:]
        if let data = try? Data(contentsOf: indexURL),
           let old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for t in old["tiles"] as? [[String: Any]] ?? [] { index[t["tile"] as? String ?? ""] = t }
        }
        for (x, y) in tiles {
            let name = "\(z)/\(x)/\(y)"
            print(name)
            let folder = out.appendingPathComponent("\(z)/\(x)/\(y)")
            var state: [String: Any] = ["tile": name, "folder": "out/tiles/\(z)/\(x)/\(y)"]
            let started = Date()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // A stale GLB would pass validation after a failed build.
                for stale in ["placement.json", "metadata.json", "validation.json", "stats.json", "tile_\(z)_\(x)_\(y).glb"] {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(stale))
                }
                let tile = try Tile(folder: Fetch.folder(z: z, x: x, y: y))
                let t0 = Date()
                try Build.run(tile: tile, out: folder, whole: true, export: true, samples: options.samples)
                state["build_s"] = round(Date().timeIntervalSince(t0) * 10) / 10
                print(String(format: "  build     ok in %.1f s", state["build_s"] as! Double))
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
