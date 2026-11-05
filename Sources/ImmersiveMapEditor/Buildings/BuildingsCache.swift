import Foundation
import TileKit

/// The Buildings view's buildings of a tile kept as `buildings.bin` beside
/// its osm.json (`BinaryCache`, stamped by the JSON): the outlines and
/// parts with their tags and polygons in metres, as last made from the
/// OSM, so a tile opens without the OSM's elements being read and its
/// closed ways and multipolygons made into shapes again (the user,
/// 2026-11-03: a format of our own instead of JSON). The tags' strings
/// are interned in one table.
enum BuildingsCache {
    static let name = "buildings.bin"
    static let magic = "BLDG"
    static let version: UInt32 = 2

    static func read(folder: URL, stamp: String) -> [OsmBuilding]? {
        guard var r = BinaryCache.read(folder.appendingPathComponent(name), magic: magic, version: version, stamp: stamp) else { return nil }
        do {
            var strings: [String] = []
            for _ in 0..<(try r.count()) { strings.append(try r.string()) }
            var out: [OsmBuilding] = []
            for _ in 0..<(try r.count()) {
                let id = try r.string()
                let part = try r.uint8() != 0
                let monument = try r.uint8() != 0, point = try r.uint8() != 0
                var tags: Tags = [:]
                for _ in 0..<(try r.count()) {
                    let k = Int(try r.uint32()), v = Int(try r.uint32())
                    guard k < strings.count, v < strings.count else { throw BinaryReader.Short() }
                    tags[strings[k]] = strings[v]
                }
                var polygons: [[[Vec2]]] = []
                for _ in 0..<(try r.count()) {
                    var rings: [[Vec2]] = []
                    for _ in 0..<(try r.count()) {
                        var ring: [Vec2] = []
                        for _ in 0..<(try r.count()) { ring.append(Vec2(try r.double(), try r.double())) }
                        rings.append(ring)
                    }
                    polygons.append(rings)
                }
                out.append(OsmBuilding(id: id, tags: tags, polygons: polygons, isPart: part, monument: monument, point: point))
            }
            return out
        } catch {
            return nil
        }
    }

    static func write(_ buildings: [OsmBuilding], folder: URL, stamp: String) {
        var strings: [String: UInt32] = [:]
        var table: [String] = []
        func intern(_ s: String) -> UInt32 {
            if let i = strings[s] { return i }
            let i = UInt32(table.count)
            strings[s] = i
            table.append(s)
            return i
        }
        var body = BinaryWriter()
        body.count(buildings.count)
        for b in buildings {
            body.string(b.id)
            body.uint8(b.isPart ? 1 : 0)
            body.uint8(b.monument ? 1 : 0)
            body.uint8(b.point ? 1 : 0)
            body.count(b.tags.count)
            for (k, v) in b.tags.sorted(by: { $0.key < $1.key }) {
                body.uint32(intern(k))
                body.uint32(intern(v))
            }
            body.count(b.polygons.count)
            for rings in b.polygons {
                body.count(rings.count)
                for ring in rings {
                    body.count(ring.count)
                    for p in ring {
                        body.double(p.x)
                        body.double(p.y)
                    }
                }
            }
        }
        var w = BinaryCache.writer(magic: magic, version: version, stamp: stamp)
        w.count(table.count)
        for s in table { w.string(s) }
        var data = w.data
        data.append(body.data)
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}
