/// osm2streets's `update_geometry`: recalculates an intersection's polygon
/// and the trims of its roads. Idempotent.

import StreetGeom

extension StreetNetwork {
    mutating func updateGeometry(_ id: IntersectionID) {
        let i = intersections[id]!
        let inputRoads = i.roads.map { roads[$0]!.toInputRoad(config.drivingSide) }
        do {
            let results = try intersectionPolygon(i.id, i.kind, inputRoads, i.trimRoadsForMerging)
            intersections.modify(id) { $0.polygon = results.intersectionPolygon }
            for (r, dist) in results.trimStarts { roads.modify(r) { $0.trimStart = dist } }
            for (r, dist) in results.trimEnds { roads.modify(r) { $0.trimEnd = dist } }
        } catch {
            // Don't trim the lines back at all.
            let road = roads[i.roads[0]]!
            let pt = road.srcI == i.id ? road.referenceLine.firstPt() : road.referenceLine.lastPt()
            intersections.modify(id) { $0.polygon = Circle(center: pt, radius: .meters(3.0)).toPolygon() }
        }
        let drivingSide = config.drivingSide
        for r in intersections[id]!.roads {
            roads.modify(r) { road in
                let untrimmed = road.getUntrimmedCenterLine(drivingSide)
                if let pl = Road.trimPolylineBothEnds(untrimmed, road.trimStart, road.trimEnd) {
                    road.centerLine = pl
                } else {
                    road.centerLine = untrimmed
                    // Collapse it later.
                    road.internalJunctionRoad = true
                }
            }
        }
    }

    /// Every road reachable from `start` within `rounds` hops.
    public func findNearbyRoads(_ start: RoadID, _ rounds: Int) -> Set<RoadID> {
        var found: Set<RoadID> = [start]
        var queue = [start]
        for _ in 0..<rounds {
            var nextQueue: [RoadID] = []
            for r in queue {
                for i in roads[r]!.endpoints() {
                    for next in intersections[i]!.roads where !found.contains(next) {
                        nextQueue.append(next)
                        found.insert(next)
                    }
                }
            }
            queue = nextQueue
        }
        return found
    }
}
