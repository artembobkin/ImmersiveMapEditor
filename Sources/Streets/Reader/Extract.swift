/// streets_reader's `OsmExtract`: the ways that become roads, the nodes'
/// ids by position, turn restrictions, traffic signals, cycle stop lines
/// and crossings.
///
/// The Rust keeps signals and crossings in `HashMap`s and later iterates
/// them in the map's random order. This port iterates them in the order they
/// were inserted (by node id); the two agree whenever no two of them write
/// the same road end, which is what the Rust's own determinism needs too.

import OSMReader
import StreetGeom

/// A map that iterates in insertion order.
struct InsertionOrderedMap<K: Hashable, V> {
    private(set) var storage: [K: V] = [:]
    private var order: [K] = []

    subscript(key: K) -> V? { storage[key] }

    mutating func insert(_ key: K, _ value: V) {
        if storage.updateValue(value, forKey: key) == nil { order.append(key) }
    }

    @discardableResult
    mutating func remove(_ key: K) -> V? {
        guard let v = storage.removeValue(forKey: key) else { return nil }
        order.removeAll { $0 == key }
        return v
    }

    var entries: [(K, V)] { order.map { ($0, storage[$0]!) } }
    var count: Int { storage.count }
}

struct OsmExtract {
    /// Unsplit roads. Several may share a way id (partly pre-split by clipping).
    var roads: [(WayID, [Pt2D], Tags)] = []
    var osmNodeIDs: [HashablePt2D: NodeID] = [:]
    var simpleTurnRestrictions: [(RestrictionType, WayID, NodeID, WayID)] = []
    var complicatedTurnRestrictions: [(RelationID, WayID, WayID, WayID)] = []
    var trafficSignals = InsertionOrderedMap<HashablePt2D, Direction?>()
    var cyclewayStopLines: [(HashablePt2D, Direction?)] = []
    var crossings = InsertionOrderedMap<HashablePt2D, Crossing>()

    mutating func handleNode(_ id: NodeID, _ node: Node) {
        osmNodeIDs[node.pt.toHashable()] = id
        if node.tags.is("highway", "traffic_signals") {
            trafficSignals.insert(node.pt.toHashable(), parseDir(node.tags.get("traffic_signals:direction")))
        }
        if node.tags.is("cycleway", "asl") {
            cyclewayStopLines.append((node.pt.toHashable(), parseDir(node.tags.get("direction"))))
        }
        if node.tags.is("highway", "crossing") || node.tags.is("railway", "crossing") {
            let kind: CrossingKind
            switch node.tags.get("crossing") {
            case "traffic_signals": kind = .signalized
            case "uncontrolled", "marked": kind = .marked
            default: kind = .unmarked
            }
            crossings.insert(node.pt.toHashable(), Crossing(kind: kind, hasIsland: node.tags.is("crossing:island", "yes")))
        }
    }

    /// True if the way was added as a road.
    @discardableResult
    mutating func handleWay(_ id: WayID, _ way: Way, _ cfg: MapConfig) -> Bool {
        let tags = way.tags
        if tags.is("area", "yes") { return false }
        if tags.is("railway", "light_rail") {
            roads.append((id, way.pts, tags))
            return true
        }
        if tags.is("railway", "rail") && cfg.includeRailroads {
            roads.append((id, way.pts, tags))
            return true
        }
        guard var highway = tags.get("highway") else { return false }
        if highway == "construction" {
            guard let x = tags.get("construction") else { return false }
            highway = x
        }
        let kept = ["busway", "cycleway", "footway", "living_street", "motorway", "motorway_link", "path", "pedestrian",
                    "primary", "primary_link", "residential", "secondary", "secondary_link", "service", "steps",
                    "tertiary", "tertiary_link", "track", "trunk", "trunk_link", "unclassified"]
        if !kept.contains(highway) { return false }
        if cfg.inferredSidewalks && tags.is("highway", "footway") && tags.isAny("footway", ["crossing", "sidewalk"]) {
            return false
        }
        if highway == "service" && tags.is("golf", "cartpath") { return false }
        roads.append((id, way.pts, tags))
        return true
    }

    /// True if the relation was used (turn restrictions only).
    @discardableResult
    mutating func handleRelation(_ id: RelationID, _ rel: Relation) -> Bool {
        if !rel.tags.is("type", "restriction") { return false }
        var fromWay: WayID?
        var viaNode: NodeID?
        var viaWay: WayID?
        var toWay: WayID?
        for (role, member) in rel.members {
            switch member {
            case .way(let w):
                if role == "from" { fromWay = w } else if role == "to" { toWay = w } else if role == "via" { viaWay = w }
            case .node(let n):
                if role == "via" { viaNode = n }
            case .relation:
                break
            }
        }
        if let restriction = rel.tags.get("restriction"), let rt = RestrictionType.new(restriction) {
            if let from = fromWay, let via = viaNode, let to = toWay {
                simpleTurnRestrictions.append((rt, from, via, to))
            } else if let from = fromWay, let via = viaWay, let to = toWay, rt == .banTurns {
                complicatedTurnRestrictions.append((id, from, via, to))
            }
        }
        return true
    }
}

func parseDir(_ x: String?) -> Direction? {
    switch x {
    case "forward": return .forward
    case "backward": return .backward
    default: return nil
    }
}
