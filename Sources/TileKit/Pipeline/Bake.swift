import Foundation
import Geometry

/// The light of a tile and every step after it: the bake, the light map's
/// shaping, the cut to the tile, TEXCOORD_1, stats.json and the export.
/// The build runs it on the scene it made (Build), and `pipeline bake`
/// runs it again on the scene a build left in bake/, with other settings,
/// so a tile's light is tuned without building its geometry.
///
/// A built tile's bake/ holds scene.bin (BakeScene) and settings.json (the
/// Lighting.Settings of its last bake). With the settings stored, a bake
/// gives the build's light map, GLB and statistics again byte for byte, but
/// the timing (`seconds`, here the bake's own) and the metadata's date.
public enum Bake {
    public static let folder = "bake"

    /// Bakes the scene's light with `settings` and writes lightmap.png and
    /// stats.json into `out`, with `export` the GLB, placement.json,
    /// metadata.json and bake/settings.json. Without `bake` the light map is
    /// plain white (a multiplier of 1: the palette as it is), small, until
    /// the light is baked (`pipeline bake`). `cutDone` hears the triangle
    /// count of the cut mesh. Returns the light map's size in pixels.
    @discardableResult
    static func light(_ scene: BakeScene, _ settings: Lighting.Settings, tile: Tile, out: URL, export: Bool, started: Date,
                      log: String, bake: Bool = true, cutDone: (Int) -> Void = { _ in }) throws -> Int {
        // The light map is `settings.size` pixels for a whole tile, whatever
        // its overhang (its texels a little coarser the further it reaches),
        // and a lab square's share of that.
        let share = (scene.region.2 - scene.region.0) / tile.size
        let size = bake ? max(64, Int((Double(settings.size) * share / 16).rounded(.toNearestOrEven)) * 16) : 64
        // The light map sees a white ground plane under the tile that the
        // model does not have (the vector tile is its ground), so walls and
        // roads keep the light they had on it.
        let lit = scene.lit
        let (x0, y0, x1, y1) = Geometry.box(lit.0, lit.1, lit.2, lit.3).buffer(20, join: .mitre).bounds
        let plane = [x0, y0, -0.01, x1, y0, -0.01, x1, y1, -0.01, x0, y0, -0.01, x1, y1, -0.01, x0, y1, -0.01]
        let light: [UInt8]
        if bake {
            print("[\(log)] baking a \(size) px light map")
            light = try Lighting.lightMap(scene.mesh.pos + plane, bounds: lit, size: size, settings: settings)
        } else {
            print("[\(log)] the light not baked: a white light map")
            light = [UInt8](repeating: 255, count: size * size * 3)
        }
        try PNG.write(out.appendingPathComponent("lightmap.png"), light, width: size, height: size, channels: 3)

        Progress.report("Cutting the tile and exporting")
        let m = cut(scene.mesh, scene.region)
        let uv1 = Lighting.lightUVs(m, bounds: lit, size: size)
        cutDone(m.count)
        // The face shade: each face's step of shade, from the whole scene
        // with the ground plane, then the palette of the names the tile
        // uses with their steps, and TEXCOORD_0 pointed at them.
        Progress.report("Shading the faces")
        let faceStarted = Date()
        let factors = bake ? try Lighting.faceFactors(m, scene: (scene.mesh.pos + plane).map(Float.init), settings: settings) : [Double](repeating: 1, count: m.count)
        let base = PaletteTexture()
        let sides = settings.sidedTones
        var names: [String] = [], index: [String: Int] = [:]
        var uv0 = [Double](repeating: 0, count: m.count * 6)
        var shadedNames: [String] = []
        // The largest palette holds 4096 cells: past that the shade's levels
        // are merged, two to one, then four, until it fits.
        var coarse = 1
        while true {
            shadedNames = (0..<m.count).map { t in
                var name = base.name(at: P2(m.uv[t * 6], m.uv[t * 6 + 1])) ?? "clay"
                if !sides { name = Palette.plain(name) }
                return Palette.shaded(name, factor: factors[t], coarse: coarse)
            }
            names = []
            index = [:]
            for name in shadedNames where index[name] == nil { index[name] = names.count; names.append(name) }
            if names.count <= 4096 || coarse >= 32 { break }
            coarse *= 2
        }
        let palette = PaletteTexture(names: names)
        for t in 0..<m.count {
            let uv = palette.uv(shadedNames[t])
            for i in 0..<3 { uv0[t * 6 + i * 2] = uv.x; uv0[t * 6 + i * 2 + 1] = uv.y }
        }
        let shaded = factors.filter { $0 < 0.999 }.count
        print(String(format: "[%@] faces: %d of %d shaded, %d colours in a %d px palette, in %.1f s", log, shaded, m.count,
                     names.count, palette.size, Date().timeIntervalSince(faceStarted)))
        try PNG.write(out.appendingPathComponent("palette.png"), palette.pixels, width: palette.size, height: palette.size, channels: 3)
        var stats = scene.stats
        stats["faces_shaded"] = shaded
        stats["palette_colours"] = names.count
        stats["triangles"] = m.count
        stats["light_baked"] = bake
        stats["light_map_px"] = size
        stats["metres_per_texel"] = 2 * scene.reach / Double(size)
        stats["seconds"] = (Date().timeIntervalSince(started) * 10).rounded() / 10
        try Export.write(stats, out.appendingPathComponent("stats.json"))
        if export {
            let glb = try Export.tile(m, uv0: uv0, uv1: uv1, palette: palette, light: light, lightSize: size, tile: tile,
                                      out: out, stats: stats, models: scene.models)
            print("[\(log)] exported \(glb.path)")
            let bake = out.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: bake, withIntermediateDirectories: true)
            try Export.write(settings.json(lightMapPixels: size), bake.appendingPathComponent("settings.json"))
        }
        return size
    }

    /// Writes the scene a build baked into the tile's bake/.
    static func store(_ scene: BakeScene, out: URL) throws {
        let bake = out.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: bake, withIntermediateDirectories: true)
        try scene.encoded().write(to: bake.appendingPathComponent("scene.bin"))
    }

    /// Bakes the light of built tiles again: each tile's stored settings,
    /// changed by `change`, then the steps after the bake and the
    /// validation. A tile with no bake/ fails (it has to be built first),
    /// and the others go on. Returns whether every tile came out valid.
    public static func run(_ paths: WorkspacePaths, z: Int, tiles: [(Int, Int)],
                           change: (inout Lighting.Settings) -> Void = { _ in }) -> Bool {
        var failed = 0
        for (x, y) in tiles {
            let name = "\(z)/\(x)/\(y)"
            print("[bake] \(name)")
            let started = Date()
            do {
                let out = paths.tileOut(z: z, x: x, y: y)
                let bake = out.appendingPathComponent(folder)
                let sceneURL = bake.appendingPathComponent("scene.bin")
                guard FileManager.default.fileExists(atPath: sceneURL.path) else {
                    throw PipelineError("out/tiles/\(name) has no \(folder)/scene.bin: build it first")
                }
                var settings = Lighting.Settings()
                if let data = try? Data(contentsOf: bake.appendingPathComponent("settings.json")),
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    settings = Lighting.Settings(json: json)
                }
                change(&settings)
                guard settings.size >= 16, settings.samples >= 1, settings.bounces >= 0 else {
                    throw PipelineError("size must be at least 16, samples at least 1, bounces at least 0")
                }
                let scene = try BakeScene(Data(contentsOf: sceneURL))
                guard scene.tile == [z, x, y] else { throw PipelineError("\(sceneURL.path) is the scene of another tile") }
                let tile = try Tile(folder: paths.tileData(z: z, x: x, y: y))
                print("[bake] size \(settings.size), \(settings.samples) samples, modifiers on: " + settings.modifiers.filter(\.on).map(\.kind).joined(separator: " "))
                try light(scene, settings, tile: tile, out: out, export: true, started: started, log: "bake")
                Progress.report("Validating")
                let result = try Validate.tile(out)
                for c in result.checks where !c.ok { print("[bake]   FAIL \(c.name) \(c.detail)") }
                print(String(format: "[bake] %@ %@ in %.1f s", name, result.ok ? "ok" : "FAILED at validate",
                             Date().timeIntervalSince(started)))
                if !result.ok { failed += 1 }
            } catch {
                print("[bake] \(name) FAILED: \(error)")
                failed += 1
            }
        }
        print("\(tiles.count - failed) tiles baked, \(failed) failed")
        return failed == 0
    }
}
