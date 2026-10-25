import Topology

/// JTS 1.20.0's `DiscreteHausdorffDistance` (`algorithm.distance`, with its
/// `DistanceToPoint` and `PointPairDistance`), translated to Swift (EDL-1.0,
/// as `Topology`) for the buffer matcher of the JTS XML runner only. The
/// matcher measured it with GEOS's `GEOSHausdorffDistanceDensify` (GEOS's
/// translation of the same class) until GEOS left the package. Not part of
/// the port: the package never asks for a Hausdorff distance.
struct DiscreteHausdorffDistance {
    let g0: Topology.Geometry
    let g1: Topology.Geometry
    /// The fraction each segment is densified by (0: not densified).
    var densifyFrac = 0.0

    init(_ g0: Topology.Geometry, _ g1: Topology.Geometry) {
        self.g0 = g0
        self.g1 = g1
    }

    /// `distance(g0, g1, densifyFrac)`: the larger of the two oriented distances.
    static func distance(_ g0: Topology.Geometry, _ g1: Topology.Geometry, densifyFrac: Double) -> Double {
        precondition(densifyFrac > 0 && densifyFrac <= 1, "Fraction is not in range (0.0 - 1.0]")
        var d = DiscreteHausdorffDistance(g0, g1)
        d.densifyFrac = densifyFrac
        return d.distance()
    }

    func distance() -> Double {
        var ptDist = PointPairDistance()
        computeOrientedDistance(g0, g1, &ptDist)
        computeOrientedDistance(g1, g0, &ptDist)
        return ptDist.distance
    }

    func orientedDistance() -> Double {
        var ptDist = PointPairDistance()
        computeOrientedDistance(g0, g1, &ptDist)
        return ptDist.distance
    }

    private func computeOrientedDistance(_ discreteGeom: Topology.Geometry, _ geom: Topology.Geometry, _ ptDist: inout PointPairDistance) {
        // MaxPointDistanceFilter: every coordinate of the discrete geometry.
        var maxPt = PointPairDistance()
        for pt in discreteGeom.getCoordinates() {
            var minPt = PointPairDistance()
            DistanceToPoint.computeDistance(geom, pt, &minPt)
            maxPt.setMaximum(minPt)
        }
        ptDist.setMaximum(maxPt)
        guard densifyFrac > 0 else { return }
        // MaxDensifiedByFractionDistanceFilter: the points along each segment.
        var maxFrac = PointPairDistance()
        let numSubSegs = Int((1.0 / densifyFrac).rounded(.toNearestOrEven))
        discreteGeom.applyComponents { c in
            guard let line = c as? LineString else { return }
            let seq = line.points
            guard seq.count > 1 else { return }
            for index in 1..<seq.count {
                let p0 = seq[index - 1], p1 = seq[index]
                let delx = (p1.x - p0.x) / Double(numSubSegs)
                let dely = (p1.y - p0.y) / Double(numSubSegs)
                for i in 0..<numSubSegs {
                    let pt = Coordinate(p0.x + Double(i) * delx, p0.y + Double(i) * dely)
                    var minPt = PointPairDistance()
                    DistanceToPoint.computeDistance(geom, pt, &minPt)
                    maxFrac.setMaximum(minPt)
                }
            }
        }
        ptDist.setMaximum(maxFrac)
    }
}

/// JTS's `PointPairDistance`: a pair of points and their distance, the
/// largest or smallest so far.
struct PointPairDistance {
    var pt = (Coordinate(0, 0), Coordinate(0, 0))
    var distance = Double.nan
    var isNull = true

    mutating func initialize(_ p0: Coordinate, _ p1: Coordinate, _ d: Double) {
        pt = (p0, p1)
        distance = d
        isNull = false
    }

    mutating func setMaximum(_ o: PointPairDistance) { setMaximum(o.pt.0, o.pt.1) }

    mutating func setMaximum(_ p0: Coordinate, _ p1: Coordinate) {
        if isNull { return initialize(p0, p1, p0.distance(p1)) }
        let d = p0.distance(p1)
        if d > distance { initialize(p0, p1, d) }
    }

    mutating func setMinimum(_ p0: Coordinate, _ p1: Coordinate) {
        if isNull { return initialize(p0, p1, p0.distance(p1)) }
        let d = p0.distance(p1)
        if d < distance { initialize(p0, p1, d) }
    }
}

/// JTS's `DistanceToPoint`: the nearest point of a geometry to a point.
enum DistanceToPoint {
    static func computeDistance(_ geom: Topology.Geometry, _ pt: Coordinate, _ ptDist: inout PointPairDistance) {
        switch geom {
        case let line as LineString: computeDistance(line, pt, &ptDist)
        case let poly as Polygon:
            computeDistance(poly.shell, pt, &ptDist)
            for h in poly.holes { computeDistance(h, pt, &ptDist) }
        case let gc as GeometryCollection:
            for g in gc.geometries { computeDistance(g, pt, &ptDist) }
        default:
            // A point.
            if let c = geom.getCoordinate() { ptDist.setMinimum(c, pt) }
        }
    }

    static func computeDistance(_ line: LineString, _ pt: Coordinate, _ ptDist: inout PointPairDistance) {
        let coords = line.points
        guard coords.count > 1 else { return }
        for i in 0..<(coords.count - 1) {
            let closest = LineSegment(coords[i], coords[i + 1]).closestPoint(pt)
            ptDist.setMinimum(closest, pt)
        }
    }
}
