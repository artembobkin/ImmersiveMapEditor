/// osm2streets's general intersection geometry, for three roads or more:
/// each pair of adjacent road edges is trimmed back to where they collide.

import StreetGeom

func trimToCorners(_ results: GeometryResults, _ roads: InputRoads, _ sortedRoadIDs: [RoadID]) throws -> GeometryResults {
    var results = results
    var roads = roads
    var sortedRoads: [Road] = []
    var origCenters: [RoadID: PolyLine] = [:]
    var intersectionEndpoints: [IntersectionID: Pt2D] = [:]
    for id in sortedRoadIDs {
        let road = roads[id]!
        sortedRoads.append(road.toRoad())
        origCenters[id] = road.centerLine
        // Approximate, overwritten in an arbitrary order: only a heuristic.
        intersectionEndpoints[road.srcI] = road.centerLine.firstPt()
        intersectionEndpoints[road.dstI] = road.centerLine.lastPt()
    }
    var edges = RoadEdge.calculate(sortedRoads, results.intersectionID)
    edges.append(edges[0])
    for k in 0..<(edges.count - 1) {
        let one = edges[k]
        let two = edges[k + 1]
        if one.road == two.road { continue }
        guard var (pt, _) = one.pl.reversed().intersection(two.pl.reversed()) else { continue }
        // PolyLine intersection misbehaves when the first points match.
        if one.pl.lastPt() == two.pl.lastPt() { pt = one.pl.lastPt() }
        let road1 = roads[one.road]!
        let road2 = roads[two.road]!
        if CommonEndpoint((road1.srcI, road1.dstI), (road2.srcI, road2.dstI)) == .both {
            let otherI = road1.srcI == results.intersectionID ? road1.dstI : road1.srcI
            let distToThis = intersectionEndpoints[results.intersectionID]!.distTo(pt)
            let distToOther = intersectionEndpoints[otherI]!.distTo(pt)
            if distToOther < distToThis { continue }
        }
        for side in [one, two] {
            guard let (_, angle) = side.pl.distAlongOfPoint(pt) else { continue }
            let perp = InfiniteLine.fromPtAngle(pt, angle.rotateDegs(90.0))
            var centerAway = origCenters[side.road]!
            if roads[side.road]!.dstI == results.intersectionID { centerAway = centerAway.reversed() }
            var trimCandidates: [PolyLine] = []
            for trimTo in allIntersectionInfinite(centerAway, perp) {
                if let s = centerAway.getSliceStartingAt(trimTo) { trimCandidates.append(s) }
            }
            if var trimmed = trimCandidates.rustMaxByKey({ $0.length }) {
                if trimmed.length < roads[side.road]!.centerLine.length {
                    if roads[side.road]!.dstI == results.intersectionID { trimmed = trimmed.reversed() }
                    roads.modify(side.road) { $0.centerLine = trimmed }
                }
            }
        }
    }
    results.intersectionPolygon = try polygonFromCorners(roads, sortedRoadIDs, origCenters, results.intersectionID)
    for road in roads.values { results.trimmedCenterPts[road.id] = road.centerLine }
    return results
}

/// Every point where a polyline hits an infinite line.
func allIntersectionInfinite(_ pl: PolyLine, _ other: InfiniteLine) -> [Pt2D] {
    var hits: [Pt2D] = []
    for l in pl.lines() {
        if let h = l.intersectionInfinite(other) { hits.append(h) }
    }
    return hits
}
