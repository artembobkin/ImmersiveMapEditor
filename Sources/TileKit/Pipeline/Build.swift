import Foundation
import Geometry

/// The build of one tile, or of a square of it (a lab, to judge the look
/// before a whole tile is built): its landmarks, buildings, roads,
/// construction sites and shelters as one mesh, the light baked from above,
/// cut to the region.
///
/// The region is in local metres around the tile's centre. The light map's
/// size follows the region's share of the tile, so its density per metre is
/// the one a whole tile has (`light.size` over the tile, 1024).
///
/// Writes into the output folder: palette.png, lightmap.png and stats.json,
/// and with `export` the GLB, placement.json, metadata.json and bake/ (the
/// scene and settings of the light, so Bake can bake it again).
public enum Build {
    /// Metres built around the region for the light map.
    static let margin = 40.0

    public static func run(_ paths: WorkspacePaths, tile: Tile, out: URL, region square: (Double, Double, Double)? = nil, whole: Bool = false,
                           export: Bool = false, light: Lighting.Settings = Lighting.Settings(), bakeLight: Bool = true,
                           roads: URL? = nil) throws {
        guard whole || !export else { throw PipelineError("export needs the whole tile: a model covers its whole tile") }
        let started = Date()
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let (cx, cy, half) = whole ? (0.0, 0.0, tile.size / 2) : (square ?? (-30, -130, 160))
        let region = Geometry.box(cx - half, cy - half, cx + half, cy + half)
        let work = region.buffer(margin, join: .mitre)
        Progress.report("Reading OSM")
        let osm = try Osm(tile)
        Progress.report("Placing the landmarks")
        // The landmark models first: their colours join the palette.
        // A whole tile takes the landmark models standing in it alone.
        let (models, replaced, covered) = Imported.load(tile, work, paths, within: whole ? region : nil)
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
        for (i, bd) in buildings.enumerated() {
            Progress.report("Building the houses", fraction: Double(i + 1) / Double(buildings.count),
                            detail: "\(i + 1) of \(buildings.count)")
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
        Progress.report("Laying the roads")
        let (asphalt, kerb, shelters) = try Ground.build(b, osm, tile, work: work, footprint: footprint, paths: paths, roads: roads)
        Progress.report("Construction sites and bus shelters")
        buildSites(b, osm: osm, work: work, earth: Ground.constructionEarth(osm, work: work, footprint: footprint,
                                                                            asphalt: asphalt, kerb: kerb),
                   footprint: footprint, asphalt: asphalt)
        let furniture = buildFurniture(b, shelters: shelters)
        Progress.report("Cleaning the mesh")
        let m = clean(b.tris)

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
        let ordinaryCount = buildings.filter { $0.landmark == nil }.count
        // The statistics that do not depend on the light: Bake adds the rest.
        var stats: [String: Any] = [
            "region": ["centre": [cx, cy], "half": half],
            "triangles_by_kind": b.counts,
            "ordinary_buildings_and_parts": ordinaryCount, "landmarks_pending": pending,
            "landmark_model_faces": landmarks.made, "landmark_windows": landmarks.windows,
            "landmark_windows_by_model": landmarks.byModel, "overhang_m": overhang,
        ]
        for (k, v) in furniture { stats[k] = v }
        let scene = BakeScene(tile: [tile.z, tile.x, tile.y], models: models.map { $0.id }, stats: stats,
                              region: region.bounds, lit: lit, reach: reach, mesh: m)
        // An exported tile keeps its scene, so its light can be baked again.
        if export { try Bake.store(scene, out: out) }
        try Bake.light(scene, light, tile: tile, out: out, export: export, started: started, log: "lab", bake: bakeLight) { count in
            print("[lab] \(ordinaryCount) ordinary buildings and parts, landmarks \(pending), \(count) triangles")
        }
    }
}
