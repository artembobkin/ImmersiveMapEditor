import Foundation
import Geometry

/// The light of a tile and every step after it: the bake, the light map's
/// shaping, the cut to the tile, TEXCOORD_1, stats.json and the export.
/// The build runs it on the scene it made (Build), and `tilepipeline bake`
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
    /// metadata.json and bake/settings.json. `cutDone` hears the triangle
    /// count of the cut mesh. Returns the light map's size in pixels.
    @discardableResult
    static func light(_ scene: BakeScene, _ settings: Lighting.Settings, tile: Tile, out: URL, export: Bool, started: Date,
                      log: String, cutDone: (Int) -> Void = { _ in }) throws -> Int {
        let size = max(64, Int((Double(settings.size) * (2 * scene.reach) / tile.size / 16).rounded(.toNearestOrEven)) * 16)
        // The light map sees a white ground plane under the tile that the
        // model does not have (the vector tile is its ground), so walls and
        // roads keep the light they had on it.
        let lit = scene.lit
        let (x0, y0, x1, y1) = Geometry.box(lit.0, lit.1, lit.2, lit.3).buffer(20, join: .mitre).bounds
        let plane = [x0, y0, -0.01, x1, y0, -0.01, x1, y1, -0.01, x0, y0, -0.01, x1, y1, -0.01, x0, y1, -0.01]
        print("[\(log)] baking a \(size) px light map")
        let irradiance = try Lighting.bake(scene.mesh.pos + plane, bounds: lit, size: size, samples: settings.samples,
                                           bounces: settings.bounces)
        let light = Lighting.shape(irradiance, settings)
        try PNG.write(out.appendingPathComponent("lightmap.png"), light, width: size, height: size, channels: 3)

        let m = cut(scene.mesh, scene.region)
        let uv1 = Lighting.lightUVs(m, bounds: lit, size: size)
        cutDone(m.count)
        var stats = scene.stats
        stats["triangles"] = m.count
        stats["light_map_px"] = size
        stats["metres_per_texel"] = tile.size / Double(settings.size)
        stats["seconds"] = (Date().timeIntervalSince(started) * 10).rounded() / 10
        try Export.write(stats, out.appendingPathComponent("stats.json"))
        if export {
            let glb = try Export.tile(m, uv1: uv1, palette: PaletteTexture(), light: light, lightSize: size, tile: tile,
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
                print("[bake] size \(settings.size), \(settings.samples) samples, \(settings.bounces) bounces, gamma \(settings.gamma)")
                try light(scene, settings, tile: tile, out: out, export: true, started: started, log: "bake")
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
