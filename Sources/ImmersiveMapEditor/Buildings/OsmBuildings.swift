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
    /// Its height in metres, by `height` or `building:levels`, nil without.
    var height: Double? { length(tags["height"]) ?? length(tags["building:levels"]).map { $0 * 3.4 } }
    var minHeight: Double { TileKit.minHeight(tags) }
    var area: Double { polygons.reduce(0) { $0 + abs(signedArea($1[0])) - $1.dropFirst().reduce(0) { $0 + abs(signedArea($1)) } } }

    /// Whether a point is inside it.
    func contains(_ p: Vec2) -> Bool {
        polygons.contains { rings in rings.reduce(0) { $0 + winding($1, p) } != 0 }
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
    var picked: Set<String> = []
    private(set) var status = ""

    var selected: [OsmBuilding] { all.filter { picked.contains($0.id) } }

    /// Reads the buildings of `tile` from its OSM, unless they are read.
    func load(_ tile: TileKey?, paths: WorkspacePaths) async {
        guard tile != self.tile else { return }
        self.tile = tile
        all = []
        picked = []
        projection = nil
        guard let tile else { return }
        status = "Reading the tile's OSM…"
        let folder = paths.tileData(z: tile.z, x: tile.x, y: tile.y)
        let read = await Task.detached { () -> (Tile, [OsmBuilding])? in
            guard let t = try? Tile(folder: folder), let osm = try? Osm(t) else { return nil }
            let buildings = osm.areas().compactMap { a -> OsmBuilding? in
                let part = a.tags["building:part"] != nil && a.tags["building:part"] != "no"
                guard part || (a.tags["building"] != nil && a.tags["building"] != "no") else { return nil }
                let polygons = a.shape.polygons.map { p in [p.exterior] + p.interiors }.map { $0.map { $0.map { Vec2($0.x, $0.y) } } }
                return OsmBuilding(id: "\(a.kind)/\(a.id)", tags: a.tags, polygons: polygons, isPart: part)
            }
            return (t, buildings)
        }.value
        guard self.tile == tile else { return }
        guard let (t, buildings) = read else {
            status = "No OSM for the tile yet."
            return
        }
        projection = t
        let half = t.size / 2
        square = (Vec2(-half, -half), Vec2(half, half))
        // Outlines first, parts over them, as they are drawn.
        all = buildings.sorted { !$0.isPart && $1.isPart }
        status = "\(buildings.filter { !$0.isPart }.count) buildings, \(buildings.filter(\.isPart).count) parts"
    }

    /// The building under a point: the smallest that holds it, a part before
    /// the outline it stands on.
    func building(at p: Vec2) -> OsmBuilding? {
        all.filter { $0.contains(p) }.min { $0.area < $1.area }
    }
}
