import Foundation
import Geometry

/// The OSM elements of a fetched area (osm.json, Overpass's JSON) as shapes
/// in local metres: nodes, ways and relations in the file's order, closed
/// ways and multipolygons as areas, tagged ways as lines.

public struct OsmNode {
    public let id: Int64
    public let lat, lon: Double
    public let tags: Tags
}

public struct OsmWay {
    public let id: Int64
    public let nodes: [Int64]
    public let tags: Tags
}

public struct OsmMember {
    public let type: String
    public let ref: Int64
    public let role: String
}

public struct OsmRelation {
    public let id: Int64
    public let members: [OsmMember]
    public let tags: Tags
}

/// The fetched elements (osm.json in the projection's folder) as shapes in
/// local metres, in the file's order.
public final class Osm {
    public let projection: Projecting
    public private(set) var nodes: [Int64: OsmNode] = [:]
    public private(set) var nodeOrder: [Int64] = []
    public private(set) var ways: [Int64: OsmWay] = [:]
    public private(set) var wayOrder: [Int64] = []
    public private(set) var relations: [OsmRelation] = []
    private var points: [Int64: P2] = [:]

    /// The elements as read: what `OsmCache` keeps.
    struct Elements {
        var nodes: [Int64: OsmNode] = [:]
        var nodeOrder: [Int64] = []
        var ways: [Int64: OsmWay] = [:]
        var wayOrder: [Int64] = []
        var relations: [OsmRelation] = []

        /// The elements as Overpass's JSON has them (type, id, lat, lon,
        /// nodes, members, tags), nodes then ways then relations, for what
        /// still takes that form: the seed's OSM XML, the fetch's summary.
        var overpass: [[String: Any]] {
            var out: [[String: Any]] = []
            for id in nodeOrder {
                guard let n = nodes[id] else { continue }
                var e: [String: Any] = ["type": "node", "id": n.id, "lat": n.lat, "lon": n.lon]
                if !n.tags.isEmpty { e["tags"] = n.tags }
                out.append(e)
            }
            for id in wayOrder {
                guard let w = ways[id] else { continue }
                var e: [String: Any] = ["type": "way", "id": w.id, "nodes": w.nodes]
                if !w.tags.isEmpty { e["tags"] = w.tags }
                out.append(e)
            }
            for r in relations {
                var e: [String: Any] = ["type": "relation", "id": r.id,
                                        "members": r.members.map { ["type": $0.type, "ref": $0.ref, "role": $0.role] as [String: Any] }]
                if !r.tags.isEmpty { e["tags"] = r.tags }
                out.append(e)
            }
            return out
        }
    }

    /// The folder's OSM read: its osm.bin, or an osm.json found there
    /// converted into it (`OsmCache`; the user, 2026-11-03).
    public init(_ projection: Projecting) throws {
        self.projection = projection
        let e = try OsmCache.elements(in: projection.folder)
        nodes = e.nodes
        nodeOrder = e.nodeOrder
        ways = e.ways
        wayOrder = e.wayOrder
        relations = e.relations
    }

    /// Whether a tile's folder holds its OSM, fetched: osm.bin, or an
    /// osm.json not converted yet.
    public static func isFetched(_ folder: URL) -> Bool { OsmCache.isThere(folder) }

    /// What a tile's OSM is now, for a cache derived from it (the editor's
    /// buildings): another after a fetch.
    public static func sourceStamp(_ folder: URL) -> String { OsmCache.stamp(of: folder) }

    /// Overpass's JSON parsed: its elements in the file's order.
    static func parse(_ data: Data) throws -> Elements {
        var out = Elements()
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        for case let e as [String: Any] in root["elements"] as? [Any] ?? [] {
            guard let type = e["type"] as? String, let id = (e["id"] as? NSNumber)?.int64Value else { continue }
            let tags = e["tags"] as? Tags ?? [:]
            switch type {
            case "node":
                out.nodes[id] = OsmNode(id: id, lat: (e["lat"] as? NSNumber)?.doubleValue ?? 0,
                                        lon: (e["lon"] as? NSNumber)?.doubleValue ?? 0, tags: tags)
                out.nodeOrder.append(id)
            case "way":
                out.ways[id] = OsmWay(id: id, nodes: (e["nodes"] as? [NSNumber] ?? []).map(\.int64Value), tags: tags)
                out.wayOrder.append(id)
            case "relation":
                let members = (e["members"] as? [[String: Any]] ?? []).map {
                    OsmMember(type: $0["type"] as? String ?? "", ref: ($0["ref"] as? NSNumber)?.int64Value ?? 0,
                              role: $0["role"] as? String ?? "")
                }
                out.relations.append(OsmRelation(id: id, members: members, tags: tags))
            default:
                break
            }
        }
        return out
    }

    public func point(_ node: Int64) -> P2 {
        if let p = points[node] { return p }
        let n = nodes[node]!
        let p = projection.metres(lat: n.lat, lon: n.lon)
        points[node] = p
        return p
    }

    public func wayCoords(_ way: OsmWay) -> [P2] { way.nodes.filter { nodes[$0] != nil }.map(point) }

    public func wayPolygon(_ way: OsmWay) -> Geometry? {
        let c = wayCoords(way)
        guard c.count >= 4, way.nodes.first == way.nodes.last else { return nil }
        let poly = Geometry.polygon(c)
        return poly.isValid ? poly : poly.buffer(0)
    }

    public func wayLine(_ way: OsmWay) -> Geometry? {
        let c = wayCoords(way)
        return c.count >= 2 ? .lineString(c) : nil
    }

    /// A multipolygon's area: its outer ways joined into rings, less its
    /// inner ones.
    public func relationPolygon(_ relation: OsmRelation) -> Geometry? {
        func rings(_ role: String) -> Geometry? {
            let lines = relation.members.compactMap { m -> Geometry? in
                guard m.type == "way", m.role == role, let w = ways[m.ref] else { return nil }
                return wayLine(w)
            }
            guard !lines.isEmpty else { return nil }
            let merged = Geometry.collection(lines).lineMerge()
            return .unaryUnion(Geometry.polygonize(merged.lines).parts)
        }
        guard let outer = rings("outer"), !outer.isEmpty else { return nil }
        let inner = rings("inner")
        let area = inner.map { $0.isEmpty ? outer : outer.difference($0) } ?? outer
        return area.isValid ? area : area.buffer(0)
    }

    /// Every closed way and multipolygon: (kind, id, tags, shape).
    public func areas() -> [(kind: String, id: Int64, tags: Tags, shape: Geometry)] {
        if let cached = areaCache { return cached }
        var out: [(String, Int64, Tags, Geometry)] = []
        for id in wayOrder {
            let way = ways[id]!
            if !way.tags.isEmpty, way.nodes.first == way.nodes.last, let poly = wayPolygon(way), !poly.isEmpty {
                out.append(("way", id, way.tags, poly))
            }
        }
        for rel in relations where rel.tags["type"] == "multipolygon" {
            if let poly = relationPolygon(rel), !poly.isEmpty { out.append(("relation", rel.id, rel.tags, poly)) }
        }
        areaCache = out
        return out
    }

    private var areaCache: [(kind: String, id: Int64, tags: Tags, shape: Geometry)]?
    private var lineCache: [(id: Int64, tags: Tags, line: Geometry)]?

    /// Every tagged way as a line: (id, tags, line).
    public func lines() -> [(id: Int64, tags: Tags, line: Geometry)] {
        if let cached = lineCache { return cached }
        var out: [(Int64, Tags, Geometry)] = []
        for id in wayOrder {
            let way = ways[id]!
            if !way.tags.isEmpty, let line = wayLine(way) { out.append((id, way.tags, line)) }
        }
        lineCache = out
        return out
    }
}
