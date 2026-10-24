import Foundation
import Geometry

// Sorting the OSM buildings of a tile: which are ordinary, which belong to a
// landmark (landmarks/landmarks.json), which are left out (config/exclude.json).
//
// A building that has `building:part`s is drawn by its parts (Simple 3D
// Buildings), and the part of its outline no part covers by the outline's own
// tags. Parts inherit the tags of the outline they stand in, under the
// `_outline:` prefix (`outlineTags` reads them back), and its id as `_key`,
// so all parts of one building take the same colours.

func loadJSON(_ url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return json
}

/// A `building=construction` stands only when OSM gives its height: in
/// Moscow that is mostly a standing house under restoration, while one
/// without levels is the outline of a house still to be built.
func unbuilt(_ tags: Tags) -> Bool {
    tags["building"] == "construction" && tags["building:levels"] == nil && tags["height"] == nil
}

public final class Building {
    /// "way/123" or "relation/123".
    public let id: String
    public var tags: Tags
    public let poly: Geometry
    /// The outline it belongs to (its own id for an outline), if any.
    public let outline: String?
    public var landmark: String?
    /// The point of its whole outline: the tile it stands in owns it.
    public var anchor: Geometry = .empty

    init(_ id: String, _ tags: Tags, _ poly: Geometry, _ outline: String? = nil) {
        self.id = id
        self.tags = tags
        self.poly = poly
        self.outline = outline
    }
}

/// The buildings and parts to draw in `work`, each with its landmark id or
/// nil, and the union of their footprints on the ground. The OSM elements
/// in `replaced` stand for a model of Modeling (`Imported`) and are left
/// out, as is a building or part standing mostly in `covered`, the models'
/// plan.
public func sortBuildings(osm: Osm, work: Geometry, paths: WorkspacePaths, replaced: Set<String> = [],
                          covered: Geometry? = nil) -> (buildings: [Building], footprint: Geometry) {
    let exclude = (loadJSON(paths.config.appendingPathComponent("exclude.json"))["exclude"] as? [[String: Any]] ?? [])
        .compactMap { $0["element"] as? String }
    let excluded = Set(exclude).union(replaced)
    let registry = loadJSON(paths.landmarks.appendingPathComponent("landmarks.json"))["landmarks"] as? [[String: Any]] ?? []
    var shapes: [String: Geometry] = [:]
    var outlines: [(String, Tags, Geometry)] = [], parts: [(String, Tags, Geometry)] = []
    // Every building of the data, not only those in `work`: whether an
    // outline has parts must not depend on which tile is being built.
    for area in osm.areas() {
        let name = "\(area.kind)/\(area.id)"
        let tags = area.tags
        shapes[name] = area.shape
        if excluded.contains(name) || underground(tags) { continue }
        for poly in area.shape.simplify(0.4).polygons {
            if poly.area < 2 { continue }
            if let covered, tags["building"] != nil || tags["building:part"] != nil,
               poly.intersects(covered), poly.intersection(covered).area > 0.5 * poly.area {
                continue
            }
            if let part = tags["building:part"], part != "no" {
                parts.append((name, tags, poly))
            } else if let kind = tags["building"], kind != "no", kind != "roof", !unbuilt(tags) {
                var t = tags
                t["_key"] = name
                outlines.append((name, t, poly))
            }
        }
    }

    let tree = STRtree(outlines.map { $0.2 })
    var owned: [Int: [Geometry]] = [:]
    var buildings: [Building] = []
    for (name, tags, poly) in parts {
        // The outline a part stands in: the one covering most of it (a
        // part's own point can fall just outside a simplified outline).
        let cover = tree.query(poly).map { (outlines[$0].2.intersection(poly).area, $0) }
            .filter { $0.0 > 0.5 * poly.area }
        if let owner = cover.max(by: { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 })?.1 {
            owned[owner, default: []].append(poly)
            let o = outlines[owner]
            var t = tags
            t["_key"] = o.0
            for (k, v) in o.1 { t[outlinePrefix + k] = v }
            buildings.append(Building(name, t, poly, o.0))
        } else {
            buildings.append(Building(name, tags, poly))
        }
    }
    // An outline is drawn by its parts, and where its parts leave some of it
    // uncovered (a tower mapped as a part, the base below it only as the
    // outline), the rest is drawn by the outline's own tags.
    for (i, (name, tags, poly)) in outlines.enumerated() {
        var rest = poly
        if let mine = owned[i] {
            rest = poly.difference(.unaryUnion(mine)).buffer(-0.3, join: .mitre).buffer(0.3, join: .mitre)
        }
        for piece in rest.polygons where piece.area >= 4 {
            buildings.append(Building(name, tags, piece, name))
        }
    }
    buildings = buildings.filter { $0.poly.intersects(work) }
    // A building belongs to the one tile its whole outline's point stands
    // in, the same point whichever tile is built: every part of it with it.
    for b in buildings {
        let whole = b.outline.flatMap { shapes[$0] }
        b.anchor = (whole ?? b.poly).representativePoint
    }

    // Landmarks: by the outline a building or part belongs to, or by the
    // area its footprint stands in.
    var byOutline: [String: String] = [:]
    var areas: [(String, Geometry)] = []
    for lm in registry {
        guard let id = lm["id"] as? String else { continue }
        for o in lm["outlines"] as? [String] ?? [] { byOutline[o] = id }
        for a in lm["areas"] as? [String] ?? [] {
            if let s = shapes[a] { areas.append((id, s.buffer((lm["area_buffer_m"] as? NSNumber)?.doubleValue ?? 0))) }
        }
    }
    for b in buildings {
        b.landmark = b.outline.flatMap { byOutline[$0] } ?? byOutline[b.id]
        if b.landmark == nil {
            let point = b.poly.representativePoint
            b.landmark = areas.first { $0.1.contains(point) }?.0
        }
    }

    // The ground is left out only under what stands on it: an outline whose
    // parts are all raised (a gallery, a bridge) keeps its ground.
    // A landmark waiting for its model is not built, so its ground stays.
    let footprint = Geometry.unaryUnion(buildings.filter { minHeight($0.tags) < 0.5 && $0.landmark == nil }.map(\.poly))
    return (buildings, footprint)
}
