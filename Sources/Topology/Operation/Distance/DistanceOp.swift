/// The distance between two geometries and their nearest points: zero when
/// an element of one is in a polygon of the other, else the least distance
/// between their segments and points, with envelopes to skip what cannot
/// be nearer: JTS's `DistanceOp`, as GEOS 3.13 runs it (the second
/// geometry's polygons tried first for containment, segment envelopes
/// compared by their squared distance).
public final class DistanceOp {
    private let geom: [Geometry]
    private let terminateDistance: Double
    @exclusivity(unchecked) private var ptLocator = PointLocator()
    @exclusivity(unchecked) private var minDistanceLocation: [GeometryLocation?] = [nil, nil]
    // GEOS starts from infinity (JTS: the largest double), which only an
    // infinite or NaN distance tells apart.
    @exclusivity(unchecked) private var minDistance = Double.infinity
    @exclusivity(unchecked) private var computed = false

    public static func distance(_ g0: Geometry, _ g1: Geometry) -> Double { DistanceOp(g0, g1).distance() }

    /// Whether the distance is at most `distance`, false when either is
    /// empty (as GEOS 3.13: JTS compares the empty's distance of 0).
    public static func isWithinDistance(_ g0: Geometry, _ g1: Geometry, _ distance: Double) -> Bool {
        if g0.isEmpty() || g1.isEmpty() { return false }
        if g0.getEnvelopeInternal().distance(g1.getEnvelopeInternal()) > distance { return false }
        return DistanceOp(g0, g1, distance).distance() <= distance
    }

    /// The nearest points, the first of `g0`; nil when either is empty.
    public static func nearestPoints(_ g0: Geometry, _ g1: Geometry) -> [Coordinate]? { DistanceOp(g0, g1).nearestPoints() }

    public init(_ g0: Geometry, _ g1: Geometry, _ terminateDistance: Double = 0.0) {
        geom = [g0, g1]
        self.terminateDistance = terminateDistance
    }

    public func distance() -> Double {
        if geom[0].isEmpty() || geom[1].isEmpty() { return 0.0 }
        if let p0 = geom[0] as? Point, let p1 = geom[1] as? Point {
            return p0.getCoordinate()!.distance(p1.getCoordinate()!)
        }
        computeMinDistance()
        return minDistance
    }

    public func nearestPoints() -> [Coordinate]? {
        computeMinDistance()
        guard let l0 = minDistanceLocation[0], let l1 = minDistanceLocation[1] else { return nil }
        return [l0.coordinate, l1.coordinate]
    }

    public func nearestLocations() -> [GeometryLocation?] {
        computeMinDistance()
        return minDistanceLocation
    }

    private func updateMinDistance(_ locGeom: [GeometryLocation?], _ flip: Bool) {
        guard locGeom[0] != nil else { return }
        minDistanceLocation = flip ? [locGeom[1], locGeom[0]] : [locGeom[0], locGeom[1]]
    }

    private func computeMinDistance() {
        if computed { return }
        computed = true
        computeContainmentDistance()
        if minDistance <= terminateDistance { return }
        computeFacetDistance()
    }

    private static func polygons(_ g: Geometry) -> [Polygon] {
        var polys: [Polygon] = []
        g.applyGeometries { if let p = $0 as? Polygon { polys.append(p) } }
        return polys
    }

    /// The first point of each element (point, line, polygon).
    private static func locations(_ g: Geometry) -> [GeometryLocation] {
        var locs: [GeometryLocation] = []
        g.applyGeometries { e in
            if e.isEmpty() { return }
            if e is Point || e is LineString || e is Polygon { locs.append(GeometryLocation(e, 0, e.getCoordinate()!)) }
        }
        return locs
    }

    private func computeContainmentDistance() {
        let polys1 = DistanceOp.polygons(geom[1])
        if !polys1.isEmpty, let (loc, polyLoc) = computeInside(DistanceOp.locations(geom[0]), polys1) {
            minDistanceLocation = [loc, polyLoc]
            return
        }
        let polys0 = DistanceOp.polygons(geom[0])
        if !polys0.isEmpty, let (loc, polyLoc) = computeInside(DistanceOp.locations(geom[1]), polys0) {
            minDistanceLocation = [polyLoc, loc]
        }
    }

    /// The first location inside a polygon, with that polygon's location.
    private func computeInside(_ locs: [GeometryLocation], _ polys: [Polygon]) -> (GeometryLocation, GeometryLocation)? {
        for loc in locs {
            for poly in polys where Location.exterior != ptLocator.locate(loc.coordinate, poly) {
                minDistance = 0.0
                return (loc, GeometryLocation(poly, loc.coordinate))
            }
        }
        return nil
    }

    private func computeFacetDistance() {
        let lines0 = LinearComponentExtracter.getLines(geom[0])
        let lines1 = LinearComponentExtracter.getLines(geom[1])
        var locGeom: [GeometryLocation?] = [nil, nil]
        computeMinDistanceLines(lines0, lines1, &locGeom)
        updateMinDistance(locGeom, false)
        if minDistance <= terminateDistance { return }
        let pts1 = DistanceOp.points(geom[1])
        locGeom = [nil, nil]
        computeMinDistanceLinesPoints(lines0, pts1, &locGeom)
        updateMinDistance(locGeom, false)
        if minDistance <= terminateDistance { return }
        let pts0 = DistanceOp.points(geom[0])
        locGeom = [nil, nil]
        computeMinDistanceLinesPoints(lines1, pts0, &locGeom)
        updateMinDistance(locGeom, true)
        if minDistance <= terminateDistance { return }
        locGeom = [nil, nil]
        computeMinDistancePoints(pts0, pts1, &locGeom)
        updateMinDistance(locGeom, false)
    }

    private static func points(_ g: Geometry) -> [Point] {
        var pts: [Point] = []
        g.applyGeometries { if let p = $0 as? Point { pts.append(p) } }
        return pts
    }

    private func computeMinDistanceLines(_ lines0: [LineString], _ lines1: [LineString], _ locGeom: inout [GeometryLocation?]) {
        for line0 in lines0 {
            for line1 in lines1 {
                computeMinDistance(line0, line1, &locGeom)
                if minDistance <= terminateDistance { return }
            }
        }
    }

    private func computeMinDistancePoints(_ points0: [Point], _ points1: [Point], _ locGeom: inout [GeometryLocation?]) {
        for pt0 in points0 {
            for pt1 in points1 {
                guard let c0 = pt0.getCoordinate(), let c1 = pt1.getCoordinate() else { continue }
                let dist = c0.distance(c1)
                if dist < minDistance {
                    minDistance = dist
                    locGeom = [GeometryLocation(pt0, 0, c0), GeometryLocation(pt1, 0, c1)]
                }
                if minDistance <= terminateDistance { return }
            }
        }
    }

    private func computeMinDistanceLinesPoints(_ lines: [LineString], _ points: [Point], _ locGeom: inout [GeometryLocation?]) {
        for line in lines {
            for pt in points where !pt.isEmpty() {
                computeMinDistance(line, pt, &locGeom)
                if minDistance <= terminateDistance { return }
            }
        }
    }

    private func computeMinDistance(_ line0: LineString, _ line1: LineString, _ locGeom: inout [GeometryLocation?]) {
        let lineEnv0 = line0.getEnvelopeInternal(), lineEnv1 = line1.getEnvelopeInternal()
        if lineEnv0.distance(lineEnv1) > minDistance { return }
        let coord0 = line0.points, coord1 = line1.points
        for i in stride(from: 0, to: coord0.count - 1, by: 1) {
            let p00 = coord0[i], p01 = coord0[i + 1]
            let segEnv0 = Envelope(p00, p01)
            if segEnv0.distanceSquared(lineEnv1) > minDistance * minDistance { continue }
            for j in stride(from: 0, to: coord1.count - 1, by: 1) {
                let p10 = coord1[j], p11 = coord1[j + 1]
                if segEnv0.distanceSquared(Envelope(p10, p11)) > minDistance * minDistance { continue }
                let dist = Distance.segmentToSegment(p00, p01, p10, p11)
                if dist < minDistance {
                    minDistance = dist
                    let closestPt = LineSegment(p00, p01).closestPoints(LineSegment(p10, p11))
                    locGeom = [GeometryLocation(line0, i, closestPt[0]), GeometryLocation(line1, j, closestPt[1])]
                }
                if minDistance <= terminateDistance { return }
            }
        }
    }

    private func computeMinDistance(_ line: LineString, _ pt: Point, _ locGeom: inout [GeometryLocation?]) {
        if line.getEnvelopeInternal().distance(pt.getEnvelopeInternal()) > minDistance { return }
        let coord0 = line.points
        let coord = pt.getCoordinate()!
        for i in stride(from: 0, to: coord0.count - 1, by: 1) {
            let dist = Distance.pointToSegment(coord, coord0[i], coord0[i + 1])
            if dist < minDistance {
                minDistance = dist
                let segClosestPoint = LineSegment(coord0[i], coord0[i + 1]).closestPoint(coord)
                locGeom = [GeometryLocation(line, i, segClosestPoint), GeometryLocation(pt, 0, coord)]
            }
            if minDistance <= terminateDistance { return }
        }
    }
}

extension Geometry {
    /// The distance to another geometry (0 when either is empty): GEOS's
    /// `Geometry::distance`, which is `DistanceOp`.
    public func distance(_ g: Geometry) -> Double { DistanceOp.distance(self, g) }

    public func isWithinDistance(_ g: Geometry, _ distance: Double) -> Bool { DistanceOp.isWithinDistance(self, g, distance) }
}

extension LineSegment {
    /// The nearest points of two segments, this one's first: the
    /// intersection, else the nearest of the four end to segment pairs.
    public func closestPoints(_ line: LineSegment) -> [Coordinate] {
        if let intPt = intersection(line) { return [intPt, intPt] }
        let close00 = closestPoint(line.p0)
        var minDistance = close00.distance(line.p0)
        var closestPt = [close00, line.p0]
        let close01 = closestPoint(line.p1)
        var dist = close01.distance(line.p1)
        if dist < minDistance {
            minDistance = dist
            closestPt = [close01, line.p1]
        }
        let close10 = line.closestPoint(p0)
        dist = close10.distance(p0)
        if dist < minDistance {
            minDistance = dist
            closestPt = [p0, close10]
        }
        let close11 = line.closestPoint(p1)
        dist = close11.distance(p1)
        if dist < minDistance { closestPt = [p1, close11] }
        return closestPt
    }
}
