import Foundation
import TileKit

/// A tile's OSM buildings and named streets read from its folder, with no
/// window: what the Buildings view shows (`OsmBuildings`) and what the
/// area's automation makes landmarks of (`AreaMCP`), read one way.
enum TileBuildings {
    /// The buildings, building parts and monuments of a tile's OSM folder,
    /// as last made from this OSM and kept beside it (`BuildingsCache`),
    /// else made from the OSM and kept; nil when the tile has no OSM.
    static func read(folder: URL) -> (tile: Tile, buildings: [OsmBuilding])? {
        guard let t = try? Tile(folder: folder) else { return nil }
        let stamp = Osm.sourceStamp(folder)
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
    }

    /// The named streets of a tile: name and polyline in the tile's metres.
    static func streets(folder: URL) -> [(name: String, points: [Vec2])] {
        guard let t = try? Tile(folder: folder), let osm = try? Osm(t) else { return [] }
        return osm.wayOrder.compactMap { id -> (String, [Vec2])? in
            guard let way = osm.ways[id], way.tags["highway"] != nil, let name = way.tags["name"] else { return nil }
            let points = osm.wayCoords(way).map { Vec2($0.x, $0.y) }
            return points.count >= 2 ? (name, points) : nil
        }
    }

    /// The name of the street nearest to a point, within `within` metres.
    static func nearestStreet(to p: Vec2, in streets: [(name: String, points: [Vec2])], within: Double = 200) -> String? {
        var best: (String, Double)?
        for street in streets {
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
}
