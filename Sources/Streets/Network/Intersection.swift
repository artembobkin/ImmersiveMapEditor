/// osm2streets's `Intersection`: where roads meet, its polygon, kind,
/// control, crossing and movements, with the clockwise sorting of its roads.

import OSMReader
import StreetGeom

public enum IntersectionKind: Hashable, Sendable {
    case mapEdge, terminus, connection, fork, intersection

    public var rustDebug: String {
        switch self {
        case .mapEdge: return "MapEdge"
        case .terminus: return "Terminus"
        case .connection: return "Connection"
        case .fork: return "Fork"
        case .intersection: return "Intersection"
        }
    }
}

public enum IntersectionControl: Hashable, Sendable {
    case uncontrolled, signed, signalled, construction

    public var rustDebug: String {
        switch self {
        case .uncontrolled: return "Uncontrolled"
        case .signed: return "Signed"
        case .signalled: return "Signalled"
        case .construction: return "Construction"
        }
    }
}

public enum CrossingKind: Int, Hashable, Comparable, Sendable {
    case unmarked, marked, signalized

    public static func < (a: CrossingKind, b: CrossingKind) -> Bool { a.rawValue < b.rawValue }

    public var rustName: String {
        switch self {
        case .unmarked: return "Unmarked"
        case .marked: return "Marked"
        case .signalized: return "Signalized"
        }
    }
}

public struct Crossing: Equatable, Sendable {
    public var kind: CrossingKind
    /// A pedestrian refuge island.
    public var hasIsland: Bool
}

/// The path some group of lanes can take through an intersection.
public typealias Movement = (RoadID, RoadID)

/// A key of `trim_roads_for_merging`: a road and whether its start is meant.
struct RoadEnd: Hashable, Comparable {
    var road: RoadID
    var start: Bool
    static func < (a: RoadEnd, b: RoadEnd) -> Bool { a.road != b.road ? a.road < b.road : (!a.start && b.start) }
}

public struct Intersection: Sendable {
    public var id: IntersectionID
    /// The OSM nodes of this intersection.
    public var osmIDs: [NodeID]
    public var polygon: Polygon
    public var kind: IntersectionKind
    public var control: IntersectionControl
    /// Clockwise around the intersection.
    public var roads: [RoadID]
    public var movements: [Movement]
    public var crossing: Crossing?
    /// Where roads were trimmed to when a short road was collapsed.
    var trimRoadsForMerging: [RoadEnd: Pt2D] = [:]

    public func isMapEdge() -> Bool { kind == .mapEdge }
}

extension StreetNetwork {
    /// A new intersection on some OSM nodes, its polygon a small circle for now.
    public mutating func insertIntersection(_ osmIDs: [NodeID], _ point: Pt2D, _ kind: IntersectionKind,
                                            _ control: IntersectionControl) -> IntersectionID {
        let id = nextIntersectionID()
        intersections[id] = Intersection(id: id, osmIDs: osmIDs,
                                         polygon: Circle(center: point, radius: .meters(3.0)).toPolygon(), kind: kind,
                                         control: control, roads: [], movements: [], crossing: nil)
        return id
    }

    /// Restores the clockwise order of an intersection's roads.
    public mutating func sortRoads(_ i: IntersectionID) {
        let intersection = intersections[i]!
        if intersection.roads.count < 2 { return }
        var roadCenters: [(RoadID, PolyLine, Pt2D)] = []
        var endpointsForCenter: [Pt2D] = []
        for r in intersection.roads {
            let road = roads[r]!
            let centerPl: PolyLine
            if road.srcI == i {
                centerPl = road.referenceLine.reversed()
            } else if road.dstI == i {
                centerPl = road.referenceLine
            } else {
                fatalError("Incident road \(r) doesn't have an endpoint at \(i)")
            }
            endpointsForCenter.append(centerPl.lastPt())
            roadCenters.append((r, centerPl, Pt2D.zero()))
        }
        let intersectionCenter = Pt2D.center(endpointsForCenter)
        let shortestCenter = roadCenters.map { $0.1.length }.min()!
        for k in roadCenters.indices {
            let pl = roadCenters[k].1
            roadCenters[k].2 = pl.mustDistAlong(pl.length - shortestCenter).0
        }
        roadCenters = roadCenters.stableSorted { rustAsI64($0.2.angleTo(intersectionCenter).normalizedDegrees()) }
        intersections.modify(i) { $0.roads = roadCenters.map(\.0) }
    }

    /// Updates the geometry (and attached roads) and the movements.
    public mutating func updateI(_ i: IntersectionID) {
        updateGeometry(i)
        updateMovements(i)
    }

    mutating func updateMovements(_ i: IntersectionID) {
        if intersections[i]!.kind == .mapEdge { return }
        let (movements, kind) = calculateMovementsAndKind(i)
        intersections.modify(i) {
            $0.movements = movements
            $0.kind = kind
        }
    }

    func calculateMovementsAndKind(_ i: IntersectionID) -> ([Movement], IntersectionKind) {
        let roads = roadsPerIntersection(i).filter { $0.isDriveable() }
        if roads.count == 1 { return ([], .terminus) }
        var connections: [(Int, Int)] = []
        for s in 0..<roads.count {
            for d in 0..<roads.count {
                if s == d { continue }
                let src = roads[s]
                if !src.canDriveOutOfEnd(i) { continue }
                let dst = roads[d]
                if !dst.canDriveIntoEnd(i) { continue }
                if src.allowedToTurnTo(dst.id) { connections.append((s, d)) }
            }
        }
        var worst = TrafficConflict.uncontested
        for a in 0..<connections.count {
            for b in (a + 1)..<connections.count {
                worst = max(worst, calcConflict(connections[a], connections[b], config.drivingSide))
                if worst == .cross { break }
            }
        }
        let kind: IntersectionKind
        switch worst {
        case .uncontested: kind = .connection
        case .diverge, .merge: kind = .fork
        case .cross: kind = .intersection
        }
        return (connections.map { (roads[$0.0].id, roads[$0.1].id) }, kind)
    }
}

enum TrafficConflict: Int, Comparable {
    case uncontested, diverge, merge, cross
    static func < (a: TrafficConflict, b: TrafficConflict) -> Bool { a.rawValue < b.rawValue }
}

/// How two movements through an intersection conflict, by the clockwise
/// indices of their roads.
func calcConflict(_ a: (Int, Int), _ b: (Int, Int), _ side: DrivingSide) -> TrafficConflict {
    if a.0 == b.0 && a.1 == b.1 { return .uncontested }
    if a.0 == b.0 { return .diverge }
    if a.1 == b.1 { return .merge }
    let isDrivingSideBetween = (side == .left) != (a.0 < a.1)
    if a.0 == b.1 { return isDrivingSideBetween != isBetween(b.0, a) ? .cross : .uncontested }
    if a.1 == b.0 { return isDrivingSideBetween != isBetween(b.1, a) ? .cross : .uncontested }
    if isBetween(a.0, b) != isBetween(a.1, b) { return .cross }
    return .uncontested
}

func isBetween(_ num: Int, _ range: (Int, Int)) -> Bool {
    let bot = min(range.0, range.1)
    let top = max(range.0, range.1)
    return bot < num && num < top
}
