/// osm2streets's intersection geometry: trims the roads back where their
/// edges meet and builds the intersection's polygon, choosing the method by
/// the number and kind of roads.

import StreetGeom

struct GeometryResults {
    var intersectionID: IntersectionID
    var intersectionPolygon: Polygon
    /// Only trimmed, or the first or last line lengthened.
    var trimmedCenterPts: [RoadID: PolyLine] = [:]
    var trimStarts: [RoadID: Distance] = [:]
    var trimEnds: [RoadID: Distance] = [:]
}

/// The roads of an intersection by id, as the Rust's `BTreeMap<RoadID, InputRoad>`.
typealias InputRoads = SortedMap<RoadID, InputRoad>

/// Trims all the roads of an intersection and makes its polygon. The roads
/// are untrimmed and sorted clockwise.
func intersectionPolygon(_ intersectionID: IntersectionID, _ kind: IntersectionKind, _ inputRoads: [InputRoad],
                         _ trimRoadsForMerging: [RoadEnd: Pt2D]) throws -> GeometryResults {
    var roads = InputRoads()
    var sortedRoads: [RoadID] = []
    for r in inputRoads {
        sortedRoads.append(r.id)
        roads[r.id] = r
    }
    let blank = GeometryResults(intersectionID: intersectionID, intersectionPolygon: .dummy())
    // Collapsing degenerate intersections recalculates in the middle of a change.
    if roads.isEmpty { return blank }
    var untrimmedRoads = roads
    var results: GeometryResults
    if roads.count == 1 {
        results = try terminus(blank, roads.values[0], kind)
    } else if roads.count == 2 {
        let values = roads.values
        results = try degenerate(blank, values[0], values[1])
    } else if !trimRoadsForMerging.isEmpty {
        results = try pretrimmedGeometry(blank, roads, sortedRoads, trimRoadsForMerging)
    } else if let r = onOffRamp(blank, roads, sortedRoads) {
        results = r
    } else {
        results = try trimToCorners(blank, roads, sortedRoads)
    }
    for r in results.trimmedCenterPts.keys.sorted() {
        let pl = results.trimmedCenterPts[r]!
        let road = untrimmedRoads.removeValue(forKey: r)!
        let trim = road.centerLine.length - pl.length
        if road.srcI == intersectionID {
            results.trimStarts[r] = trim
        } else {
            results.trimEnds[r] = trim
        }
    }
    return results
}

/// The final polygon from the endpoints of each road edge and the corners
/// where the edges originally met.
func polygonFromCorners(_ roads: InputRoads, _ sortedRoadIDs: [RoadID], _ origCenters: [RoadID: PolyLine],
                        _ i: IntersectionID) throws -> Polygon {
    let sorted = sortedRoadIDs.map { roads[$0]!.toRoad() }
    var edges = RoadEdge.calculate(sorted, i)
    edges.append(edges[0])
    var endpts: [Pt2D] = []
    for k in 0..<(edges.count - 1) {
        let one = edges[k]
        let two = edges[k + 1]
        endpts.append(one.pl.lastPt())
        if one.road != two.road {
            let a = one.pl.extendToLength(origCenters[one.road]!.length).reversed()
            let b = two.pl.extendToLength(origCenters[two.road]!.length).reversed()
            if let (corner, _) = a.intersection(b) {
                if let (dist, _) = one.pl.distAlongOfPoint(corner), dist < one.pl.length / 2.0 {
                    continue
                }
                endpts.append(corner)
            }
        }
    }
    endpts.append(endpts[0])
    return try Ring.dedupingNew(endpts).intoPolygon()
}

/// Dead ends and map edges: a piece of the road is the intersection.
func terminus(_ results: GeometryResults, _ road: InputRoad, _ kind: IntersectionKind) throws -> GeometryResults {
    var results = results
    var center = road.centerLinePointedAt(results.intersectionID)
    let intersectionLen: Distance
    if kind == .mapEdge {
        let minRoadLen = 3.0 * road.totalWidth
        if center.length < minRoadLen { center = center.extendToLength(minRoadLen) }
        intersectionLen = road.totalWidth
    } else {
        intersectionLen = center.length > road.totalWidth + .meters(1.0) ? road.totalWidth : 0.4 * center.length
    }
    var endpts = [try center.shiftLeft(road.halfWidth()).lastPt(), try center.shiftRight(road.halfWidth()).lastPt()]
    center = try center.maybeExactSlice(.zero, center.length - intersectionLen)
    endpts.append(try center.shiftRight(road.halfWidth()).lastPt())
    endpts.append(try center.shiftLeft(road.halfWidth()).lastPt())
    endpts.append(endpts[0])
    results.intersectionPolygon = try Ring.dedupingNew(endpts).intoPolygon()
    if road.srcI == results.intersectionID { center = center.reversed() }
    results.trimmedCenterPts[road.id] = center
    return results
}

/// Exactly two roads: trim each back a little.
func degenerate(_ results: GeometryResults, _ road1: InputRoad, _ road2: InputRoad) throws -> GeometryResults {
    var results = results
    var center1 = road1.centerLinePointedAt(results.intersectionID)
    var center2 = road2.centerLinePointedAt(results.intersectionID)
    let idealTrimBack = Distance.meters(1.0)
    let minTrimBack = Distance.meters(0.1)
    if center1.length < 2.0 * minTrimBack || center2.length < 2.0 * minTrimBack {
        throw GeomError.message("Road is too short to trim for a degenerate intersection")
    }
    center1 = center1.length > 2.0 * idealTrimBack
        ? center1.exactSlice(.zero, center1.length - idealTrimBack)
        : center1.exactSlice(.zero, center1.length - minTrimBack)
    center2 = center2.length > 2.0 * idealTrimBack
        ? center2.exactSlice(.zero, center2.length - idealTrimBack)
        : center2.exactSlice(.zero, center2.length - minTrimBack)
    var endpts = [
        try center1.shiftLeft(road1.halfWidth()).lastPt(),
        try center2.shiftRight(road2.halfWidth()).lastPt(),
        try center2.shiftLeft(road2.halfWidth()).lastPt(),
        try center1.shiftRight(road1.halfWidth()).lastPt(),
    ]
    endpts.append(endpts[0])
    results.intersectionPolygon = try Ring.dedupingNew(endpts).intoPolygon()
    if road1.srcI == results.intersectionID { center1 = center1.reversed() }
    if road2.srcI == results.intersectionID { center2 = center2.reversed() }
    results.trimmedCenterPts[road1.id] = center1
    results.trimmedCenterPts[road2.id] = center2
    return results
}

/// After a short road was collapsed: use the recorded trims, not the corners.
func pretrimmedGeometry(_ results: GeometryResults, _ roads: InputRoads, _ sortedRoads: [RoadID],
                        _ trimRoadsForMerging: [RoadEnd: Pt2D]) throws -> GeometryResults {
    var results = results
    var roads = roads
    var origCenters: [RoadID: PolyLine] = [:]
    for id in sortedRoads { origCenters[id] = roads[id]!.centerLine }
    for id in roads.keys {
        var road = roads[id]!
        let atStart = road.srcI == results.intersectionID
        if let endpt = trimRoadsForMerging[RoadEnd(road: road.id, start: atStart)] {
            if atStart {
                if let pl = road.centerLine.safeGetSliceStartingAt(endpt) { road.centerLine = pl }
            } else {
                precondition(road.dstI == results.intersectionID)
                if let pl = road.centerLine.safeGetSliceEndingAt(endpt) { road.centerLine = pl }
            }
            roads[id] = road
        }
    }
    results.intersectionPolygon = try polygonFromCorners(roads, sortedRoads, origCenters, results.intersectionID)
    for id in roads.keys { results.trimmedCenterPts[id] = roads[id]!.centerLine }
    return results
}
