/// osm2streets's transformations of a street network, applied in place. The
/// standard sequence for clipped areas collapses `junction=intersection`
/// roads and degenerate intersections.

import StreetGeom

public enum Transformation: Sendable {
    case zipSidepaths
    case collapseShortRoads
    case collapseDegenerateIntersections
    case removeDisconnectedRoads
    /// Only shows debugging output in the Rust, so a no-op here.
    case mergeDualCarriageways

    /// For tests and small clipped areas. Doesn't remove disconnected roads.
    public static func standardForClippedAreas() -> [Transformation] {
        [.collapseShortRoads, .collapseDegenerateIntersections, .collapseShortRoads]
    }

    func apply(_ streets: inout StreetNetwork) {
        switch self {
        case .zipSidepaths: streets.zipSidepaths()
        case .collapseShortRoads: collapseAllJunctionRoads(&streets)
        case .collapseDegenerateIntersections: collapseDegenerate(&streets)
        case .removeDisconnectedRoads: streets.removeDisconnectedRoads()
        case .mergeDualCarriageways: break
        }
    }
}

extension StreetNetwork {
    public mutating func applyTransformations(_ transformations: [Transformation]) {
        for t in transformations { t.apply(&self) }
    }
}

/// Collapses every road marked `junction=intersection`.
func collapseAllJunctionRoads(_ streets: inout StreetNetwork) {
    var queue: [RoadID] = []
    for road in streets.roads.values where road.internalJunctionRoad { queue.append(road.id) }
    for id in queue where streets.roads.contains(id) {
        try? streets.collapseShortRoad(id)
    }
}

/// Collapses intersections of two roads that are alike and have no crossing.
func collapseDegenerate(_ streets: inout StreetNetwork) {
    var merge: [IntersectionID] = []
    for intersection in streets.intersections.values {
        if intersection.crossing != nil { continue }
        let roads = streets.roadsPerIntersection(intersection.id)
        if roads.count != 2 { continue }
        if shouldCollapse(roads[0], roads[1]) { merge.append(intersection.id) }
    }
    for i in merge { streets.collapseIntersection(i) }
}

func shouldCollapse(_ road1: Road, _ road2: Road) -> Bool {
    if !road1.turnRestrictions.isEmpty || !road1.complicatedTurnRestrictions.isEmpty { return false }
    if !road2.turnRestrictions.isEmpty || !road2.complicatedTurnRestrictions.isEmpty { return false }
    if road1.onewayForDriving() != nil && road2.onewayForDriving() != nil && road1.dstI == road2.dstI { return false }
    if road1.laneSpecsLTR != road2.laneSpecsLTR { return false }
    if road1.name != road2.name { return false }
    if road1.highwayType != road2.highwayType { return false }
    if road1.layer != road2.layer { return false }
    guard case .consistent(let p1) = road1.referenceLinePlacement,
          case .consistent(let p2) = road2.referenceLinePlacement else { return false }
    return p1 == p2
}
