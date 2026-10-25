import Darwin

/// A segment of two points: JTS's `LineSegment`, a value. Sums of products
/// are fused as GEOS's compiler fuses them (`Fused.swift`).
public struct LineSegment: Equatable, CustomStringConvertible {
    public var p0: Coordinate
    public var p1: Coordinate

    public init(_ p0: Coordinate, _ p1: Coordinate) {
        self.p0 = p0
        self.p1 = p1
    }

    public init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
        self.init(Coordinate(x0, y0), Coordinate(x1, y1))
    }

    public init() { self.init(Coordinate(0, 0), Coordinate(0, 0)) }

    public func getCoordinate(_ i: Int) -> Coordinate { i == 0 ? p0 : p1 }

    public var minX: Double { javaMin(p0.x, p1.x) }
    public var maxX: Double { javaMax(p0.x, p1.x) }
    public var minY: Double { javaMin(p0.y, p1.y) }
    public var maxY: Double { javaMax(p0.y, p1.y) }

    public func getLength() -> Double { p0.distance(p1) }
    public var isHorizontal: Bool { p0.y == p1.y }
    public var isVertical: Bool { p0.x == p1.x }

    /// The side of this segment the other is on: 1 left, -1 right, 0 both
    /// or collinear.
    public func orientationIndex(_ seg: LineSegment) -> Int {
        let o0 = Orientation.index(p0, p1, seg.p0)
        let o1 = Orientation.index(p0, p1, seg.p1)
        if o0 >= 0 && o1 >= 0 { return max(o0, o1) }
        if o0 <= 0 && o1 <= 0 { return min(o0, o1) }
        return 0
    }

    public func orientationIndex(_ p: Coordinate) -> Int { Orientation.index(p0, p1, p) }

    public mutating func reverse() { swap(&p0, &p1) }

    public mutating func normalize() { if p1.compareTo(p0) < 0 { reverse() } }

    public func angle() -> Double { atan2(p1.y - p0.y, p1.x - p0.x) }

    public func midPoint() -> Coordinate { LineSegment.midPoint(p0, p1) }

    public static func midPoint(_ p0: Coordinate, _ p1: Coordinate) -> Coordinate {
        Coordinate((p0.x + p1.x) / 2, (p0.y + p1.y) / 2)
    }

    public func distance(_ ls: LineSegment) -> Double { Distance.segmentToSegment(p0, p1, ls.p0, ls.p1) }
    public func distance(_ p: Coordinate) -> Double { Distance.pointToSegment(p, p0, p1) }

    public func distancePerpendicular(_ p: Coordinate) -> Double {
        if p0.equals2D(p1) { return p0.distance(p) }
        return Distance.pointToLinePerpendicular(p, p0, p1)
    }

    public func distancePerpendicularOriented(_ p: Coordinate) -> Double {
        if p0.equals2D(p1) { return p0.distance(p) }
        let dist = distancePerpendicular(p)
        if orientationIndex(p) < 0 { return -dist }
        return dist
    }

    public func pointAlong(_ fraction: Double) -> Coordinate {
        Coordinate(fusedAdd(fraction, p1.x - p0.x, p0.x), fusedAdd(fraction, p1.y - p0.y, p0.y))
    }

    public func projectionFactor(_ p: Coordinate) -> Double {
        if p == p0 { return 0.0 }
        if p == p1 { return 1.0 }
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let len = fusedAdd(dx, dx, dy * dy)
        if len <= 0.0 { return .nan }
        return fusedAdd(p.x - p0.x, dx, (p.y - p0.y) * dy) / len
    }

    public func segmentFraction(_ p: Coordinate) -> Double {
        var f = projectionFactor(p)
        if f < 0.0 { f = 0.0 } else if f > 1.0 || f.isNaN { f = 1.0 }
        return f
    }

    public func project(_ p: Coordinate) -> Coordinate {
        if p == p0 || p == p1 { return p }
        return project(p, projectionFactor(p))
    }

    func project(_ p: Coordinate, _ f: Double) -> Coordinate {
        Coordinate(fusedAdd(f, p1.x - p0.x, p0.x), fusedAdd(f, p1.y - p0.y, p0.y))
    }

    public func closestPoint(_ p: Coordinate) -> Coordinate {
        let factor = projectionFactor(p)
        if factor > 0 && factor < 1 { return project(p, factor) }
        let d0 = p0.distance(p), d1 = p1.distance(p)
        if d0 < d1 { return p0 }
        return p1
    }

    /// The intersection with another segment, if they meet.
    public func intersection(_ line: LineSegment) -> Coordinate? {
        var li = RobustLineIntersector()
        li.computeIntersection(p0, p1, line.p0, line.p1)
        return li.hasIntersection() ? li.getIntersection(0) : nil
    }

    /// The intersection of the two lines through the segments.
    public func lineIntersection(_ line: LineSegment) -> Coordinate? {
        Intersection.intersection(p0, p1, line.p0, line.p1)
    }

    /// The point at a fraction along the segment, moved by a distance to its
    /// left (right when negative). GEOS's arithmetic: the length is
    /// `sqrt(dx * dx + dy * dy)`, the sums fused (`Fused.swift`).
    public func pointAlongOffset(_ segmentLengthFraction: Double, _ offsetDistance: Double) throws -> Coordinate {
        let segx = fusedAdd(segmentLengthFraction, p1.x - p0.x, p0.x)
        let segy = fusedAdd(segmentLengthFraction, p1.y - p0.y, p0.y)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let len = fusedAdd(dx, dx, dy * dy).squareRoot()
        var ux = 0.0, uy = 0.0
        if offsetDistance != 0.0 {
            if len <= 0.0 { throw IllegalStateException("Cannot compute offset from zero-length line segment") }
            ux = offsetDistance * dx / len
            uy = offsetDistance * dy / len
        }
        return Coordinate(segx - uy, segy + ux)
    }

    /// The segment moved by a distance to its left (right when negative).
    public func offset(_ offsetDistance: Double) throws -> LineSegment {
        LineSegment(try pointAlongOffset(0, offsetDistance), try pointAlongOffset(1, offsetDistance))
    }

    public func compareTo(_ o: LineSegment) -> Int {
        let c = p0.compareTo(o.p0)
        if c != 0 { return c }
        return p1.compareTo(o.p1)
    }

    public func equalsTopo(_ o: LineSegment) -> Bool { (p0 == o.p0 && p1 == o.p1) || (p0 == o.p1 && p1 == o.p0) }

    public var description: String { "LINESTRING (\(p0.x) \(p0.y), \(p1.x) \(p1.y))" }
}
