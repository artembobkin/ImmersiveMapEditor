import Foundation
import TileKit

/// What the editor draws under the roads, from the tile's roads/seed/context.json
/// (fetch/seed_roads.py): building outlines, OSM centre lines, crossings and
/// bus stops. Read only.
struct Underlay {
    struct Road { var highway: String; var name: String?; var points: [Vec2] }
    var buildings: [[Vec2]] = []
    var roads: [Road] = []
    var crossings: [Vec2] = []
    var stops: [Vec2] = []

    static func read(_ url: URL, _ proj: Region) -> Underlay {
        var c = Underlay()
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return c }
        func point(_ any: Any?) -> Vec2 {
            guard let p = any as? [Double], p.count >= 2 else { return .zero }
            return proj.metres(lat: p[1], lon: p[0])
        }
        c.buildings = (root["buildings"] as? [Any] ?? []).map { ($0 as? [Any] ?? []).map(point) }
        for case let r as [String: Any] in root["roads"] as? [Any] ?? [] {
            c.roads.append(Road(highway: r["highway"] as? String ?? "", name: r["name"] as? String,
                                points: (r["points"] as? [Any] ?? []).map(point)))
        }
        for case let n as [String: Any] in root["nodes"] as? [Any] ?? [] {
            if n["kind"] as? String == "crossing" { c.crossings.append(point(n["point"])) } else { c.stops.append(point(n["point"])) }
        }
        return c
    }
}
