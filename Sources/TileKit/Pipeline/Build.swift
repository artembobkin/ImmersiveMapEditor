import Foundation
import Geometry

/// The build of one tile, or of a square of it (a lab, to judge the look
/// before a whole tile is built): its landmarks, buildings, roads,
/// construction sites and shelters as one mesh, the light baked from above,
/// cut to the region.
///
/// The region is in local metres around the tile's centre. The light map's
/// size follows the region's share of the tile, so its density per metre is
/// the one a whole tile has (1024 over the tile).
///
/// Writes into the output folder: palette.png, lightmap.png and stats.json,
/// and with `export` the GLB, placement.json and metadata.json.
public enum Build {
    /// Metres built around the region for the light map.
    static let margin = 40.0

    public static func run(_ paths: WorkspacePaths, tile: Tile, out: URL, region square: (Double, Double, Double)? = nil, whole: Bool = false,
                           export: Bool = false, samples: Int = 256, tileLightmap: Int = 1024, roads: URL? = nil) throws {
        let started = Date()
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let (cx, cy, half) = whole ? (0.0, 0.0, tile.size / 2) : (square ?? (-30, -130, 160))
        let region = Geometry.box(cx - half, cy - half, cx + half, cy + half)
        let work = region.buffer(margin, join: .mitre)
        let osm = try Osm(tile)
        // The landmark models first: their colours join the palette.
        let (models, replaced, covered) = Imported.load(tile, work, paths)
        let palette = PaletteTexture()
        try PNG.write(out.appendingPathComponent("palette.png"), palette.pixels, width: PaletteTexture.size,
                      height: PaletteTexture.size, channels: 3)

        let b = Builder(palette: palette)
        let landmarks = Imported.build(b, models, work, region: region)
        let (buildings, footprint) = sortBuildings(osm: osm, work: work, paths: paths, replaced: replaced, covered: covered)
        var pending: [String: Int] = [:]
        // The parts of one building take one look: a typical house only if
        // every part of it is one.
        var plainKeys = Set<String>()
        for bd in buildings where bd.landmark == nil && !typical(bd.tags) { plainKeys.insert(bd.tags["_key"] ?? bd.id) }
        for bd in buildings where plainKeys.contains(bd.tags["_key"] ?? bd.id) { bd.tags["_plain"] = "1" }
        for bd in buildings {
            if let landmark = bd.landmark {
                // A landmark is never generated: until its model is made by
                // hand, its place stays empty and is listed as pending.
                pending[landmark, default: 0] += 1
            } else {
                // Whole in the tile its anchor stands in, the light map's only
                // in a neighbour's.
                b.whole = region.contains(bd.anchor) ? .whole : .foreign
                ordinary(b, bd.id, bd.tags, bd.poly)
                b.whole = .cut
            }
        }
        let (asphalt, kerb, shelters) = try Ground.build(b, osm, tile, work: work, footprint: footprint, paths: paths, roads: roads)
        buildSites(b, osm: osm, work: work, earth: Ground.constructionEarth(osm, work: work, footprint: footprint,
                                                                            asphalt: asphalt, kerb: kerb),
                   footprint: footprint, asphalt: asphalt)
        let furniture = buildFurniture(b, shelters: shelters)
        var m = clean(b.tris)

        // The light map covers the work area and every building this tile owns
        // whole, however far it reaches over the edge, as a square around the
        // tile's centre (lightUVs maps both axes by one width).
        var reach = half + margin
        for t in 0..<m.count where m.owner[t] == .whole {
            for i in 0..<3 {
                let c = m.corner(t, i)
                reach = max(reach, abs(c.x - cx), abs(c.y - cy))
            }
        }
        let lit = (cx - reach, cy - reach, cx + reach, cy + reach)
        let overhang = (max(0, reach - half) * 100).rounded() / 100
        let size = max(64, Int((Double(tileLightmap) * (2 * reach) / tile.size / 16).rounded(.toNearestOrEven)) * 16)
        // The light map sees a white ground plane under the tile that the
        // model does not have (the vector tile is its ground), so walls and
        // roads keep the light they had on it.
        let (x0, y0, x1, y1) = Geometry.box(lit.0, lit.1, lit.2, lit.3).buffer(20, join: .mitre).bounds
        let plane = [x0, y0, -0.01, x1, y0, -0.01, x1, y1, -0.01, x0, y0, -0.01, x1, y1, -0.01, x0, y1, -0.01]
        print("[lab] baking a \(size) px light map")
        let light = Lighting.shape(try Lighting.bake(m.pos + plane, bounds: lit, size: size, samples: samples))
        try PNG.write(out.appendingPathComponent("lightmap.png"), light, width: size, height: size, channels: 3)

        m = cut(m, region.bounds)
        let uv1 = Lighting.lightUVs(m, bounds: lit, size: size)
        let ordinaryCount = buildings.filter { $0.landmark == nil }.count
        print("[lab] \(ordinaryCount) ordinary buildings and parts, landmarks \(pending), \(m.count) triangles")
        var stats: [String: Any] = [
            "region": ["centre": [cx, cy], "half": half],
            "triangles_by_kind": b.counts, "triangles": m.count,
            "ordinary_buildings_and_parts": ordinaryCount, "landmarks_pending": pending,
            "landmark_model_faces": landmarks.made, "landmark_windows": landmarks.windows,
            "landmark_windows_by_model": landmarks.byModel,
            "light_map_px": size, "overhang_m": overhang, "metres_per_texel": tile.size / Double(tileLightmap),
        ]
        for (k, v) in furniture { stats[k] = v }
        stats["seconds"] = (Date().timeIntervalSince(started) * 10).rounded() / 10
        try Export.write(stats, out.appendingPathComponent("stats.json"))
        if export {
            guard whole else { throw PipelineError("export needs the whole tile: a model covers its whole tile") }
            let glb = try Export.tile(m, uv1: uv1, palette: palette, light: light, lightSize: size, tile: tile, out: out,
                                      stats: stats, models: models.map { $0.id })
            print("[lab] exported \(glb.path)")
        }
    }
}
