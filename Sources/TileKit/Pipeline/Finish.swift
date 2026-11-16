import Foundation
import Geometry

/// The end of a build, after its mesh is made: the cut to the tile, the
/// palette of the colours the tile uses, stats.json and the export. The
/// colours are the palette's own, plain: a tile carries no light, neither
/// a light map nor a shade in its colours (the user, 2026-11-16; the build
/// baked a sky light into a second texture and darkened each face by how
/// shut in it was, with a panel of settings, and the editor had built its
/// tiles with all of it off).
extension Build {
    /// Cuts `mesh` (the tile's triangles with the margin around it) to
    /// `region` and writes palette.png and stats.json into `out`, with
    /// `export` the GLB, placement.json and metadata.json. `cutDone` hears
    /// the triangle count of the cut mesh.
    static func finish(_ mesh: Triangles, region: (Double, Double, Double, Double), stats built: [String: Any],
                       models: [String], tile: Tile, out: URL, export: Bool, started: Date, log: String,
                       cutDone: (Int) -> Void = { _ in }) throws {
        Progress.report("Cutting the tile and exporting")
        let m = cut(mesh, region)
        cutDone(m.count)
        // The palette of the names the tile uses, each without its side
        // (the side tones are a light of their own), and TEXCOORD_0 pointed
        // at them.
        let base = PaletteTexture()
        var names: [String] = [], index: [String: Int] = [:]
        let used = (0..<m.count).map { t in Palette.plain(base.name(at: P2(m.uv[t * 6], m.uv[t * 6 + 1])) ?? "clay") }
        for name in used where index[name] == nil { index[name] = names.count; names.append(name) }
        let palette = PaletteTexture(names: names)
        var uv0 = [Double](repeating: 0, count: m.count * 6)
        for t in 0..<m.count {
            let uv = palette.uv(used[t])
            for i in 0..<3 { uv0[t * 6 + i * 2] = uv.x; uv0[t * 6 + i * 2 + 1] = uv.y }
        }
        print("[\(log)] \(names.count) colours in a \(palette.size) px palette")
        try PNG.write(out.appendingPathComponent("palette.png"), palette.pixels, width: palette.size, height: palette.size, channels: 3)
        var stats = built
        stats["palette_colours"] = names.count
        stats["triangles"] = m.count
        stats["seconds"] = (Date().timeIntervalSince(started) * 10).rounded() / 10
        try Export.write(stats, out.appendingPathComponent("stats.json"))
        if export {
            let glb = try Export.tile(m, uv0: uv0, palette: palette, tile: tile, out: out, stats: stats, models: models)
            print("[\(log)] exported \(glb.path)")
        }
    }
}
