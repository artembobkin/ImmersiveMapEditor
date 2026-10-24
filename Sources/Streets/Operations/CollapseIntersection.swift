/// osm2streets's `collapse_intersection`: removes an intersection between
/// exactly two roads and joins them into one, keeping the first road's lanes.

import StreetGeom

extension StreetNetwork {
    public mutating func collapseIntersection(_ i: IntersectionID) {
        let rs = intersections[i]!.roads
        precondition(rs.count == 2)
        let keepR = rs[0]
        let destroyR = rs[1]
        precondition(keepR != destroyR)
        let fixTurnRestrictionsNear = findNearbyRoads(destroyR, 3).sorted()

        // Skip loops: they need three distinct endpoints.
        let endpts = Set(roads[keepR]!.endpoints() + roads[destroyR]!.endpoints())
        if endpts.count != 3 { return }

        var keepRoad = removeRoad(keepR)
        let destroyRoad = removeRoad(destroyR)
        _ = intersections.removeValue(forKey: i)!

        keepRoad.osmIDs.append(contentsOf: destroyRoad.osmIDs)

        var newPts: [Pt2D]
        let newSrcI: IntersectionID
        let newDstI: IntersectionID
        if keepRoad.dstI == destroyRoad.srcI {
            newPts = keepRoad.referenceLine.points + destroyRoad.referenceLine.points
            (newSrcI, newDstI) = (keepRoad.srcI, destroyRoad.dstI)
        } else if keepRoad.dstI == destroyRoad.dstI {
            newPts = keepRoad.referenceLine.points + destroyRoad.referenceLine.reversed().points
            (newSrcI, newDstI) = (keepRoad.srcI, destroyRoad.srcI)
        } else if keepRoad.srcI == destroyRoad.srcI {
            newPts = Array(destroyRoad.referenceLine.points.reversed()) + keepRoad.referenceLine.points
            (newSrcI, newDstI) = (destroyRoad.dstI, keepRoad.dstI)
        } else if keepRoad.srcI == destroyRoad.dstI {
            newPts = destroyRoad.referenceLine.points + keepRoad.referenceLine.points
            (newSrcI, newDstI) = (destroyRoad.srcI, keepRoad.dstI)
        } else {
            fatalError("unreachable")
        }
        precondition(i != newSrcI && i != newDstI)
        // Simplify curves and dedupe points.
        let epsilon = 1.0
        keepRoad.referenceLine = PolyLine.mustNew(Pt2D.simplifyRDP(newPts, epsilon))
        keepRoad.updateCenterLine(config.drivingSide)
        keepRoad.srcI = newSrcI
        keepRoad.dstI = newDstI
        insertRoad(keepRoad)

        for r in fixTurnRestrictionsNear where roads.contains(r) {
            roads.modify(r) { road in
                for k in road.turnRestrictions.indices where road.turnRestrictions[k].1 == destroyR {
                    road.turnRestrictions[k].1 = keepR
                }
                for k in road.complicatedTurnRestrictions.indices {
                    if road.complicatedTurnRestrictions[k].0 == destroyR { road.complicatedTurnRestrictions[k].0 = keepR }
                    if road.complicatedTurnRestrictions[k].1 == destroyR { road.complicatedTurnRestrictions[k].1 = keepR }
                }
            }
        }
    }
}
