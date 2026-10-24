/// osm2streets's `collapse_short_road`: removes a road and merges its two
/// intersections into one, repairing turn restrictions nearby.

import StreetGeom

extension StreetNetwork {
    public mutating func collapseShortRoad(_ shortR: RoadID) throws {
        let fixTurnRestrictionsNear = findNearbyRoads(shortR, 3).sorted()
        let (keepI, destroyIID) = (roads[shortR]!.srcI, roads[shortR]!.dstI)
        if intersections[keepI]!.kind == .mapEdge || intersections[destroyIID]!.kind == .mapEdge {
            throw GeomError.message("\(shortR) touches a map edge")
        }
        if keepI == destroyIID {
            removeRoad(shortR)
            return
        }
        var connectedToKeepI = intersections[keepI]!.roads
        var connectedToDestroyI = intersections[destroyIID]!.roads
        connectedToKeepI.removeAll { $0 == shortR }
        connectedToDestroyI.removeAll { $0 == shortR }

        var trimRoadsForMerging: [RoadEnd: Pt2D] = [:]
        for i in [keepI, destroyIID] {
            for road in roadsPerIntersection(i) where !road.internalJunctionRoad {
                if road.srcI == i {
                    trimRoadsForMerging[RoadEnd(road: road.id, start: true)] = road.centerLine.firstPt()
                } else {
                    trimRoadsForMerging[RoadEnd(road: road.id, start: false)] = road.centerLine.lastPt()
                }
            }
        }
        intersections.modify(keepI) { $0.trimRoadsForMerging.merge(trimRoadsForMerging) { _, new in new } }

        removeRoad(shortR)

        var destroyI = intersections.removeValue(forKey: destroyIID)!
        intersections.modify(keepI) { keep in
            if destroyI.control == .signalled { keep.control = .signalled }
            keep.crossing = mergeCrossings(keep.crossing, destroyI.crossing)
            keep.osmIDs.append(contentsOf: destroyI.osmIDs)
        }
        destroyI.crossing = nil

        for r in destroyI.roads {
            intersections.modify(keepI) { $0.roads.append(r) }
            var road = roads[r]!
            let loopBefore = road.srcI == road.dstI
            if road.srcI == destroyI.id {
                road.srcI = keepI
            } else {
                precondition(road.dstI == destroyI.id)
                road.dstI = keepI
            }
            roads[r] = road
            let loopAfter = road.srcI == road.dstI
            if !loopBefore && loopAfter { removeRoad(r) }
        }

        sortRoads(keepI)
        updateI(keepI)

        for r in fixTurnRestrictionsNear where roads.contains(r) {
            roads.modify(r) { road in
                var fixTRs: [(RestrictionType, RoadID)] = []
                for (rt, to) in road.turnRestrictions {
                    if to == shortR && rt == .banTurns {
                        let successors = connectedToKeepI.contains(road.id) ? connectedToDestroyI : connectedToKeepI
                        for x in successors { fixTRs.append((rt, x)) }
                    } else {
                        fixTRs.append((rt, to))
                    }
                }
                road.turnRestrictions = fixTRs
                var add: [(RestrictionType, RoadID)] = []
                road.complicatedTurnRestrictions.removeAll { via, to in
                    if via == shortR {
                        add.append((.banTurns, to))
                        return true
                    }
                    return false
                }
                road.turnRestrictions.append(contentsOf: add)
            }
        }
    }
}

func mergeCrossings(_ c1: Crossing?, _ c2: Crossing?) -> Crossing? {
    if var a = c1, let b = c2 {
        a.hasIsland = a.hasIsland || b.hasIsland
        if a.kind != b.kind { a.kind = max(a.kind, b.kind) }
        return a
    }
    return c1 ?? c2
}
