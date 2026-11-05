import Foundation
import Geometry
import Observation
import TileKit

/// One building or building part of OpenStreetMap, as the tile's OSM has
/// it: its element, all its tags, its outline in the tile's metres.
struct OsmBuilding: Identifiable {
    /// "way/123" or "relation/123".
    let id: String
    let tags: Tags
    /// Its polygons, each its outer ring then its holes.
    let polygons: [[[Vec2]]]
    /// A building:part (drawn over the outlines), not a whole building.
    let isPart: Bool
    /// A monument, not a building (the user, 2026-11-05: a statue, a
    /// helicopter on a pedestal, with a label on the engine's map and no
    /// box): historic=monument or memorial, tourism=artwork, man_made=obelisk,
    /// an area of OSM or a node, to be made a landmark and modelled.
    var monument = false
    /// An OSM node, with no outline: its polygon is a plot of
    /// `OsmBuildings.plotRadius` round it, drawn as a disc and told to the
    /// agent as a plot, not a wall.
    var point = false

    var name: String? { tags["name"] ?? tags["name:en"] }
    /// Its street and number, "Юбилейный проспект, 12", when OSM has them:
    /// the name of a landmark made of a building with no name of its own.
    var address: String? {
        guard let street = tags["addr:street"], let number = tags["addr:housenumber"] else { return nil }
        return "\(street), \(number)"
    }
    /// How much it matters, by its tags: named, notable, or plain.
    var note: BuildingNote { BuildingNote(tags) }
    /// Its height in metres, by `height` or `building:levels`, nil without.
    var height: Double? { length(tags["height"]) ?? length(tags["building:levels"]).map { $0 * 3.4 } }
    var minHeight: Double { TileKit.minHeight(tags) }
    var area: Double { polygons.reduce(0) { $0 + abs(signedArea($1[0])) - $1.dropFirst().reduce(0) { $0 + abs(signedArea($1)) } } }

    /// Whether a point is inside it.
    func contains(_ p: Vec2) -> Bool {
        polygons.contains { rings in rings.reduce(0) { $0 + winding($1, p) } != 0 }
    }

    /// The centroid of its largest outer ring, where its name sits.
    var centroid: Vec2 {
        guard let ring = polygons.map({ $0[0] }).max(by: { abs(signedArea($0)) < abs(signedArea($1)) }), ring.count >= 3 else { return middle }
        var a = 0.0, c = Vec2.zero
        for i in ring.indices {
            let p = ring[i], q = ring[(i + 1) % ring.count]
            let w = p.x * q.y - q.x * p.y
            a += w
            c = c + (p + q) * w
        }
        return abs(a) < 1e-9 ? middle : c / (3 * a)
    }

    /// A point of it, the middle of its outer rings' corners: where a part
    /// stands, to tell the building it belongs to.
    var middle: Vec2 {
        let pts = polygons.flatMap { $0[0] }
        return pts.isEmpty ? .zero : pts.reduce(.zero, +) / Double(pts.count)
    }
}

/// The buildings of the tile open, read from its OSM, what is picked of
/// them in the Buildings view, and where it looks from. Read off the main
/// thread when the tile changes.
@Observable
@MainActor
final class OsmBuildings {
    private(set) var tile: TileKey?
    private(set) var all: [OsmBuilding] = []
    /// The tile's projection: its own metres, around its centre.
    private(set) var projection: Tile?
    /// The tile's square in its metres.
    private(set) var square: (Vec2, Vec2)?
    /// Whether the tile's OSM is being read: the view shows a spinner
    /// meanwhile and frames the tile once it is read (the user, 2026-11-03).
    private(set) var loading = false
    var picked: Set<String> = []
    /// Whether the known buildings are named on the map.
    var showNames = true
    /// The building under the pointer, named in the status line.
    var hovered: String?
    private(set) var status = ""

    /// What the status line says: the building under the pointer by its
    /// name, kind and height, else the count.
    var hoverStatus: String {
        guard let id = hovered, let b = all.first(where: { $0.id == id }) else { return status }
        let kind = b.monument ? "monument" + (b.point ? " (a point)" : "")
            : b.isPart ? (b.tags["building:part"].map { $0 == "yes" ? "part" : "part, \($0)" } ?? "part")
            : (b.tags["building"].map { $0 == "yes" ? "building" : $0 } ?? "building")
        // The address too, for the houses with no name (the user, 2026-11-05:
        // the Painted Ladies are seven addresses on Steiner Street).
        return [b.name, b.address, kind, b.height.map { String(format: "%.0f m", $0) }, BuildingNote.reason(b.tags).map { "notable: \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var selected: [OsmBuilding] { all.filter { picked.contains($0.id) } }

    /// The tile's folder, for what is read of its OSM on demand.
    private var folder: URL?
    /// The named streets of the tile, read once when first asked: name and
    /// polyline in the tile's metres.
    private var streets: [(name: String, points: [Vec2])]?

    /// The name of the named street nearest to a point, within `within`
    /// metres, for naming a landmark of a building with no name and no
    /// address (the user, 2026-11-04: "Landmark 1" told nothing).
    func nearestStreet(to p: Vec2, within: Double = 200) -> String? {
        if streets == nil, let folder, let t = try? Tile(folder: folder), let osm = try? Osm(t) {
            streets = osm.wayOrder.compactMap { id -> (String, [Vec2])? in
                guard let way = osm.ways[id], way.tags["highway"] != nil, let name = way.tags["name"] else { return nil }
                let points = osm.wayCoords(way).map { Vec2($0.x, $0.y) }
                return points.count >= 2 ? (name, points) : nil
            }
        }
        var best: (String, Double)?
        for street in streets ?? [] {
            for k in 0..<(street.points.count - 1) {
                let a = street.points[k], b = street.points[k + 1], ab = b - a
                let len2 = ab.dot(ab)
                let t = len2 > 0 ? max(0, min(1, (p - a).dot(ab) / len2)) : 0
                let d = (p - (a + ab * t)).length
                if d < within, d < (best?.1 ?? .infinity) { best = (street.name, d) }
            }
        }
        return best?.0
    }

    /// Forgets the tile read, at once, for another to be opened: the view
    /// shown before the other's OSM is read has no buildings of the last
    /// tile to frame and hand to the shared camera (the user, 2026-11-03:
    /// a tile opened after another was shown where the last one was).
    func clear() {
        tile = nil
        all = []
        picked = []
        projection = nil
        square = nil
        hovered = nil
        folder = nil
        streets = nil
    }

    /// Reads the buildings of `tile` from its OSM, unless they are read.
    func load(_ tile: TileKey?, paths: WorkspacePaths) async {
        guard tile != self.tile else { return }
        self.tile = tile
        all = []
        picked = []
        projection = nil
        square = nil
        guard let tile else { return }
        let folder = paths.tileData(z: tile.z, x: tile.x, y: tile.y)
        self.folder = folder
        streets = nil
        let stamp = Osm.sourceStamp(folder)
        // A tile read before comes back at once, unless its OSM was
        // fetched again meanwhile.
        if let kept = parsed[tile], kept.stamp == stamp {
            show(kept.tile, kept.buildings)
            return
        }
        loading = true
        defer { if self.tile == tile { loading = false } }
        status = "Reading the tile's OSM…"
        let read = await Task.detached { () -> (Tile, [OsmBuilding])? in
            guard let t = try? Tile(folder: folder) else { return nil }
            // The buildings as last made from this OSM, kept beside it; else
            // made from the OSM (its own cache, or the JSON) and kept.
            if let kept = BuildingsCache.read(folder: folder, stamp: stamp) { return (t, kept) }
            guard let osm = try? Osm(t) else { return nil }
            var buildings = osm.areas().compactMap { a -> OsmBuilding? in
                let part = a.tags["building:part"] != nil && a.tags["building:part"] != "no"
                let building = part || (a.tags["building"] != nil && a.tags["building"] != "no")
                let monument = !building && BuildingNote.isMonument(a.tags)
                guard building || monument else { return nil }
                let polygons = a.shape.polygons.map { p in [p.exterior] + p.interiors }.map { $0.map { $0.map { Vec2($0.x, $0.y) } } }
                return OsmBuilding(id: "\(a.kind)/\(a.id)", tags: a.tags, polygons: polygons, isPart: part, monument: monument)
            }
            // The monuments mapped as a node: a disc of `plotRadius` round each,
            // its plot, so it is drawn, picked and made a landmark as a building is.
            for node in osm.nodes.values.sorted(by: { $0.id < $1.id }) where BuildingNote.isMonument(node.tags) {
                let c = osm.point(node.id)
                let ring = (0..<16).map { k -> Vec2 in
                    let a = Double(k) / 16 * 2 * .pi
                    return Vec2(c.x + OsmBuildings.plotRadius * cos(a), c.y + OsmBuildings.plotRadius * sin(a))
                }
                buildings.append(OsmBuilding(id: "node/\(node.id)", tags: node.tags, polygons: [[ring]], isPart: false, monument: true, point: true))
            }
            BuildingsCache.write(buildings, folder: folder, stamp: stamp)
            return (t, buildings)
        }.value
        guard self.tile == tile else { return }
        guard let (t, buildings) = read else {
            status = "No OSM for the tile yet."
            return
        }
        parsed[tile] = (t, buildings, stamp)
        order.removeAll { $0 == tile }
        order.append(tile)
        if order.count > Self.kept, let oldest = order.first {
            order.removeFirst()
            parsed[oldest] = nil
        }
        show(t, buildings)
    }

    /// The tiles read, kept for coming back to them: the last `kept`, each
    /// with the stamp of the osm.json it was read from (the user, 2026-11-03:
    /// a tile opened again waited for its OSM to be read again).
    private var parsed: [TileKey: (tile: Tile, buildings: [OsmBuilding], stamp: String)] = [:]
    private var order: [TileKey] = []
    private static let kept = 4
    /// The plot round a monument mapped as a node, in metres.
    nonisolated static let plotRadius = 5.0

    /// A tile's buildings shown: its projection and square, the buildings
    /// outlines first and parts over them, as they are drawn, the status.
    private func show(_ t: Tile, _ buildings: [OsmBuilding]) {
        projection = t
        let half = t.size / 2
        square = (Vec2(-half, -half), Vec2(half, half))
        all = buildings.sorted { !$0.isPart && $1.isPart }
        let outlines = buildings.filter { !$0.isPart }
        let monuments = buildings.filter(\.monument).count
        status = "\(outlines.count - monuments) buildings, \(buildings.filter(\.isPart).count) parts, "
            + "\(outlines.filter { $0.note == .notable && !$0.monument }.count) notable, \(outlines.filter { $0.note == .named }.count) named besides"
            + (monuments > 0 ? ", \(monuments) monument\(monuments == 1 ? "" : "s")" : "")
    }

    /// The whole building under a point: its outline (the smallest building
    /// that holds the point, or the one the part under it stands in) and
    /// every part standing in that outline. A part with no outline round it
    /// alone.
    func whole(at p: Vec2) -> [OsmBuilding] {
        let outlines = all.filter { !$0.isPart }
        var outline = outlines.filter { $0.contains(p) }.min { $0.area < $1.area }
        if outline == nil, let part = building(at: p) {
            outline = outlines.filter { $0.contains(part.middle) }.min { $0.area < $1.area }
            if outline == nil { return [part] }
        }
        guard let outline else { return [] }
        return [outline] + all.filter { $0.isPart && outline.contains($0.middle) }
    }

    /// The building under a point: the smallest that holds it, a part before
    /// the outline it stands on.
    func building(at p: Vec2) -> OsmBuilding? {
        all.filter { $0.contains(p) }.min { $0.area < $1.area }
    }
}
