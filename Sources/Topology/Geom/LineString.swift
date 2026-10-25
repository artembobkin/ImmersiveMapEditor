/// A line of two or more points, or the empty line: JTS's `LineString`. Its
/// coordinates are one contiguous array (JTS's `CoordinateSequence`).
public class LineString: Geometry {
    public static let minimumValidSize = 2

    @exclusivity(unchecked) public internal(set) var points: [Coordinate]

    init(_ points: [Coordinate], factory: GeometryFactory) {
        precondition(points.isEmpty || points.count >= LineString.minimumValidSize,
                     "Invalid number of points in LineString (found \(points.count) - must be 0 or >= 2)")
        self.points = points
        super.init(factory: factory)
    }

    override var typeCode: TypeCode { .lineString }
    override public func getGeometryType() -> String { "LineString" }
    override public func getCoordinates() -> [Coordinate] { points }
    public func getCoordinateN(_ n: Int) -> Coordinate { points[n] }
    override public func getCoordinate() -> Coordinate? { points.first }
    override public func getDimension() -> Int { 1 }
    override public func getBoundaryDimension() -> Int { isClosed() ? Dimension.false : 0 }
    override public func isEmpty() -> Bool { points.isEmpty }
    override public func getNumPoints() -> Int { points.count }
    public func getPointN(_ n: Int) -> Point { factory.createPoint(points[n]) }
    public func getStartPoint() -> Point? { isEmpty() ? nil : getPointN(0) }
    public func getEndPoint() -> Point? { isEmpty() ? nil : getPointN(points.count - 1) }

    public func isClosed() -> Bool {
        if isEmpty() { return false }
        return points[0].equals2D(points[points.count - 1])
    }

    override public func getLength() -> Double { Length.ofLine(points) }
    override public func getBoundary() -> Geometry { BoundaryOp(self).getBoundary() }

    override func reverseInternal() -> Geometry { factory.createLineString(points.reversed()) }

    public func isCoordinate(_ pt: Coordinate) -> Bool { points.contains(pt) }

    /// GEOS 3.13's envelope of a sequence: `std::min` and `std::max` of each
    /// ordinate from infinity, then sorted as `Envelope(x1, x2, y1, y2)`
    /// sorts. For finite points it is JTS's; a NaN ordinate is skipped, and
    /// a line whose x (or y) are all NaN spans from -infinity to infinity.
    override func computeEnvelopeInternal() -> Envelope {
        if points.isEmpty { return Envelope() }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for p in points {
            minX = cxxMin(minX, p.x)
            maxX = cxxMax(maxX, p.x)
            minY = cxxMin(minY, p.y)
            maxY = cxxMax(maxY, p.y)
        }
        return Envelope(minX, maxX, minY, maxY)
    }

    override public func equalsExact(_ other: Geometry, tolerance: Double) -> Bool {
        guard isEquivalentClass(other), let o = other as? LineString else { return false }
        if points.count != o.points.count { return false }
        for i in 0..<points.count where !equal(points[i], o.points[i], tolerance) { return false }
        return true
    }

    override func copyInternal() -> Geometry { LineString(points, factory: factory) }

    /// GEOS 3.13's normal form: a closed line as a clockwise ring from its
    /// least point, an open one in the direction whose first differing end
    /// is the lesser (the only case of JTS 1.20).
    override public func normalize() {
        if isClosed() && points.count >= 3 {
            points = Polygon.normalized(points, clockwise: true)
            return
        }
        for i in 0..<(points.count / 2) {
            let j = points.count - 1 - i
            if points[i] != points[j] {
                if points[i].compareTo(points[j]) > 0 { points.reverse() }
                return
            }
        }
    }

    override func isEquivalentClass(_ other: Geometry) -> Bool { other is LineString }

    /// As GEOS 3.13 compares lines: the one of more points is the greater,
    /// then point by point (JTS 1.20 compares point by point only).
    override func compareToSameClass(_ other: Geometry) -> Int {
        let line = other as! LineString
        if points.count > line.points.count { return 1 }
        if points.count < line.points.count { return -1 }
        var i = 0, j = 0
        while i < points.count && j < line.points.count {
            let c = points[i].compareTo(line.points[j])
            if c != 0 { return c }
            i += 1
            j += 1
        }
        if i < points.count { return 1 }
        if j < line.points.count { return -1 }
        return 0
    }
}
