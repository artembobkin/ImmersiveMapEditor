/// osm2streets's intersection markings: the corners where sidewalks meet,
/// and marked or unmarked crossings.

import StreetGeom

extension StreetNetwork {
    public func toIntersectionMarkingsGeoJSON(_ filter: Filter) -> String {
        var features: [GeoJSONFeature] = []
        func add(_ polygon: Polygon, _ type: String) {
            var f = GeoJSONFeature(polygon.toGeoJSON(gpsBounds))
            f.setProperty("type", .string(type))
            features.append(f)
        }
        for intersection in filter.intersections(self) {
            for p in makeSidewalkCorners(intersection) { add(p, "sidewalk corner") }
            if let crossing = intersection.crossing {
                switch crossing.kind {
                case .signalized, .marked:
                    for p in drawZebraCrossing(intersection) { add(p, "marked crossing line") }
                case .unmarked:
                    for p in drawUnmarkedCrossing(intersection) { add(p, "unmarked crossing outline") }
                }
            }
        }
        return featureCollectionString(features)
    }

    /// The corners where two sidewalks (or shoulders) meet.
    func makeSidewalkCorners(_ intersection: Intersection) -> [Polygon] {
        var edges = RoadEdge.calculate(roadsPerIntersection(intersection.id), intersection.id)
        if edges.isEmpty { return [] }
        edges.append(edges[0])
        var results: [Polygon] = []
        for k in 0..<(edges.count - 1) {
            let one = edges[k]
            let two = edges[k + 1]
            if one.road == two.road { continue }
            if !(one.lane.lt == .sidewalk || one.lane.lt == .shoulder) { continue }
            if !(two.lane.lt == .sidewalk || two.lane.lt == .shoulder) { continue }
            if roads[one.road]!.laneSpecsLTR.count == 1 || roads[two.road]!.laneSpecsLTR.count == 1 { continue }
            let outerCorner1 = one.pl.lastPt()
            let outerCorner2 = two.pl.lastPt()
            var ptsAlongIntersection: [Pt2D] = []
            if outerCorner1 == outerCorner2 {
                ptsAlongIntersection.append(outerCorner1)
            } else {
                guard let pl = intersection.polygon.getOuterRing().getShorterSliceBtwn(outerCorner1, outerCorner2) else {
                    continue
                }
                ptsAlongIntersection = pl.points
            }
            let innerPl1 = one.pl.mustShiftRight(one.lane.width)
            let innerPl2 = two.pl.mustShiftLeft(two.lane.width)
            var meetPt: Pt2D?
            if let pt = innerPl1.lastLine().infinite().intersection(innerPl2.lastLine().infinite()),
               intersection.polygon.containsPt(pt) {
                meetPt = pt
            }
            var pts = ptsAlongIntersection
            pts.append(innerPl2.lastPt())
            if let meetPt { pts.append(meetPt) }
            pts.append(innerPl1.lastPt())
            pts.append(pts[0])
            if let ring = try? Ring.dedupingNew(pts) { results.append(ring.intoPolygon()) }
        }
        return results
    }

    /// The line between the two footways of a crossing farthest apart, and
    /// the narrower of their widths.
    func getCrossingLineAndMinWidth(_ intersection: Intersection) -> (PolyLine, Distance)? {
        var candidates: [(Road, Pt2D)] = []
        for r in intersection.roads {
            let road = roads[r]!
            if road.isFootway() {
                let pl = road.dstI == intersection.id ? road.centerLine : road.centerLine.reversed()
                candidates.append((road, pl.lastPt()))
            }
        }
        var maxDist = Distance.zero
        var maxPair: ((Road, Pt2D), (Road, Pt2D))?
        for idx1 in candidates.indices {
            for idx2 in (idx1 + 1)..<max(idx1 + 1, candidates.count) {
                let dist = candidates[idx1].1.distTo(candidates[idx2].1)
                if dist > maxDist {
                    maxDist = dist
                    maxPair = (candidates[idx1], candidates[idx2])
                }
            }
        }
        guard let ((r1, pt1), (r2, pt2)) = maxPair, let pl = try? PolyLine.new([pt1, pt2]) else { return nil }
        return (pl, Swift.min(r1.totalWidth(), r2.totalWidth()))
    }

    func drawZebraCrossing(_ intersection: Intersection) -> [Polygon] {
        guard let (line, totalWidth) = getCrossingLineAndMinWidth(intersection) else { return [] }
        let width = 0.8 * totalWidth
        let thickness = Distance.meters(0.15)
        let stepSize = 3.0 * thickness
        return line.stepAlong(stepSize, stepSize).map { pt1, angle in
            let pt2 = pt1.projectAway(.meters(1.0), angle)
            return perpLine(Line.mustNew(pt1, pt2), width).makePolygons(thickness)
        }
    }

    func drawUnmarkedCrossing(_ intersection: Intersection) -> [Polygon] {
        guard let (line, totalWidth) = getCrossingLineAndMinWidth(intersection) else { return [] }
        let width = 0.8 * totalWidth
        let thickness = Distance.meters(0.15)
        var results: [Polygon] = []
        for shift in [width / 2.0, -width / 2.0] {
            if let pl = try? line.shiftEitherDirection(shift) { results.append(pl.makePolygons(thickness)) }
        }
        return results
    }
}
