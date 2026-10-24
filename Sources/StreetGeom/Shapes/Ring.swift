/// geom's `Ring`: a closed line (first point equals last), with no adjacent
/// or repeated points.

public struct Ring: Equatable, Sendable, CustomStringConvertible {
    public private(set) var points: [Pt2D]

    init(unchecked points: [Pt2D]) { self.points = points }

    public static func new(_ pts: [Pt2D]) throws -> Ring {
        if pts.count < 3 { throw bail("Can't make a ring with < 3 points") }
        if pts[0] != pts.last! { throw bail("Can't make a ring with mismatching first/last points") }
        for i in 1..<pts.count where pts[i - 1] == pts[i] {
            throw bail("Ring has duplicate adjacent points near \(pts[i - 1])")
        }
        var seen = Set<HashablePt2D>()
        for pt in pts.dropFirst() {
            if seen.contains(pt.toHashable()) { throw bail("Ring has repeat non-adjacent points near \(pt)") }
            seen.insert(pt.toHashable())
        }
        return Ring(unchecked: pts)
    }

    /// Ignores repeated non-adjacent points.
    public static func unsafeDedupingNew(_ pts: [Pt2D]) throws -> Ring {
        var pts = pts
        pts.dedup()
        if pts.count < 3 { throw bail("Can't make a ring with < 3 points") }
        if pts[0] != pts.last! { throw bail("Can't make a ring with mismatching first/last points") }
        for i in 1..<pts.count where pts[i - 1] == pts[i] {
            throw bail("Ring has duplicate adjacent points near \(pts[i - 1])")
        }
        return Ring(unchecked: pts)
    }

    public static func mustNew(_ pts: [Pt2D]) -> Ring {
        do { return try new(pts) } catch { fatalError("\(error)") }
    }

    /// First dedupes adjacent points.
    public static func dedupingNew(_ pts: [Pt2D]) throws -> Ring {
        var pts = pts
        pts.dedup()
        return try new(pts)
    }

    public func asPolyline() -> PolyLine { .uncheckedNew(points) }

    /// The ring drawn with some thickness, half inside and half outside.
    public func toOutline(_ thickness: Distance) -> Tessellation { asPolyline().thickenTessellation(thickness) }

    public func intoPolygon() -> Polygon { Polygon.withHoles(self, []) }

    /// Hits on an earlier segment of `other` come first. Deduped.
    public func allIntersections(_ other: PolyLine) -> [Pt2D] {
        var hits: [Pt2D] = []
        var seen = Set<HashablePt2D>()
        var ringLines: [Line] = []
        for i in 1..<points.count { ringLines.append(.mustNew(points[i - 1], points[i])) }
        for l1 in other.lines() {
            for l2 in ringLines {
                if let pt = l1.intersection(l2), !seen.contains(pt.toHashable()) {
                    hits.append(pt)
                    seen.insert(pt.toHashable())
                }
            }
        }
        return hits
    }

    func getBothSlicesBtwn(_ pt1: Pt2D, _ pt2: Pt2D) -> (PolyLine, PolyLine)? {
        precondition(pt1 != pt2)
        let pl = asPolyline()
        guard var dist1 = pl.distAlongOfPoint(pt1)?.0, var dist2 = pl.distAlongOfPoint(pt2)?.0 else { return nil }
        if dist1 > dist2 { swap(&dist1, &dist2) }
        if dist1 == dist2 { return nil }
        guard let candidate1 = try? pl.maybeExactSlice(dist1, dist2),
              let tail = try? pl.maybeExactSlice(dist2, pl.length),
              let head = try? pl.maybeExactSlice(.zero, dist1) else { return nil }
        return (candidate1, tail.mustExtend(head))
    }

    /// The points between two on the ring, the longer or shorter way, from `pt1` to `pt2`.
    public func getSliceBetween(_ pt1: Pt2D, _ pt2: Pt2D, _ longer: Bool) -> PolyLine? {
        if pt1 == pt2 { return nil }
        guard let (candidate1, candidate2) = getBothSlicesBtwn(pt1, pt2) else { return nil }
        let slice = longer == (candidate1.length > candidate2.length) ? candidate1 : candidate2
        return slice.firstPt() == pt1 ? slice : slice.reversed()
    }

    public func getShorterSliceBetween(_ pt1: Pt2D, _ pt2: Pt2D) -> PolyLine? { getSliceBetween(pt1, pt2, false) }

    public func getShorterSliceBtwn(_ pt1: Pt2D, _ pt2: Pt2D) -> PolyLine? {
        guard let (c1, c2) = getBothSlicesBtwn(pt1, pt2) else { return nil }
        return c1.length < c2.length ? c1 : c2
    }

    public func containsPt(_ pt: Pt2D) -> Bool { asPolyline().distAlongOfPoint(pt) != nil }

    public func toGeoJSON(_ gps: GPSBounds?) -> GeoJSONGeometry {
        let pts = gps.map { $0.convertBack(points).map { [$0.x, $0.y] } } ?? points.map { [$0.x, $0.y] }
        return .polygon([pts])
    }

    public func translate(_ dx: Double, _ dy: Double) -> Ring {
        Ring(unchecked: points.map { $0.offset(dx, dy) })
    }

    public var description: String {
        "Ring::new(vec![\n" + points.map { "  Pt2D::new(\(rustDisplay($0.x)), \(rustDisplay($0.y))),\n" }.joined() + "])"
    }
}
