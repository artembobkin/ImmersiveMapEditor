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

    var name: String? { tags["name"] ?? tags["name:en"] }
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
        let kind = b.isPart ? (b.tags["building:part"].map { $0 == "yes" ? "part" : "part, \($0)" } ?? "part")
            : (b.tags["building"].map { $0 == "yes" ? "building" : $0 } ?? "building")
        return [b.name, kind, b.height.map { String(format: "%.0f m", $0) }, BuildingNote.reason(b.tags).map { "notable: \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var selected: [OsmBuilding] { all.filter { picked.contains($0.id) } }

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
            let buildings = osm.areas().compactMap { a -> OsmBuilding? in
                let part = a.tags["building:part"] != nil && a.tags["building:part"] != "no"
                guard part || (a.tags["building"] != nil && a.tags["building"] != "no") else { return nil }
                let polygons = a.shape.polygons.map { p in [p.exterior] + p.interiors }.map { $0.map { $0.map { Vec2($0.x, $0.y) } } }
                return OsmBuilding(id: "\(a.kind)/\(a.id)", tags: a.tags, polygons: polygons, isPart: part)
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

    /// A tile's buildings shown: its projection and square, the buildings
    /// outlines first and parts over them, as they are drawn, the status.
    private func show(_ t: Tile, _ buildings: [OsmBuilding]) {
        projection = t
        let half = t.size / 2
        square = (Vec2(-half, -half), Vec2(half, half))
        all = buildings.sorted { !$0.isPart && $1.isPart }
        let outlines = buildings.filter { !$0.isPart }
        status = "\(outlines.count) buildings, \(buildings.filter(\.isPart).count) parts, "
            + "\(outlines.filter { $0.note == .notable }.count) notable, \(outlines.filter { $0.note == .named }.count) named besides"
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
