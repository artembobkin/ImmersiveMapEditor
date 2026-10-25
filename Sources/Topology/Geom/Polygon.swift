/// A polygon: an outer ring and holes, JTS's `Polygon`.
public final class Polygon: Geometry {
    @exclusivity(unchecked) public internal(set) var shell: LinearRing
    @exclusivity(unchecked) public internal(set) var holes: [LinearRing]

    init(shell: LinearRing?, holes: [LinearRing], factory: GeometryFactory) {
        let s = shell ?? factory.createLinearRing()
        precondition(!(s.isEmpty() && holes.contains { !$0.isEmpty() }), "shell is empty but holes are not")
        self.shell = s
        self.holes = holes
        super.init(factory: factory)
    }

    override var typeCode: TypeCode { .polygon }
    override public func getGeometryType() -> String { "Polygon" }
    override public func getCoordinate() -> Coordinate? { shell.getCoordinate() }

    override public func getCoordinates() -> [Coordinate] {
        if isEmpty() { return [] }
        var c = shell.points
        for h in holes { c.append(contentsOf: h.points) }
        return c
    }

    override public func getNumPoints() -> Int { holes.reduce(shell.getNumPoints()) { $0 + $1.getNumPoints() } }
    override public func getDimension() -> Int { 2 }
    override public func getBoundaryDimension() -> Int { 1 }
    override public func isEmpty() -> Bool { shell.isEmpty() }

    override public func isRectangle() -> Bool {
        if !holes.isEmpty { return false }
        if shell.getNumPoints() != 5 { return false }
        let seq = shell.points
        let env = getEnvelopeInternal()
        for i in 0..<5 {
            let x = seq[i].x
            if !(x == env.minX || x == env.maxX) { return false }
            let y = seq[i].y
            if !(y == env.minY || y == env.maxY) { return false }
        }
        var prevX = seq[0].x, prevY = seq[0].y
        for i in 1...4 {
            let x = seq[i].x, y = seq[i].y
            let xChanged = x != prevX, yChanged = y != prevY
            if xChanged == yChanged { return false }
            prevX = x
            prevY = y
        }
        return true
    }

    public func getExteriorRing() -> LinearRing { shell }
    public func getNumInteriorRing() -> Int { holes.count }
    public func getInteriorRingN(_ n: Int) -> LinearRing { holes[n] }

    override public func getArea() -> Double {
        var area = 0.0
        area += Area.ofRing(shell.points)
        for h in holes { area -= Area.ofRing(h.points) }
        return area
    }

    override public func getLength() -> Double {
        var len = 0.0
        len += shell.getLength()
        for h in holes { len += h.getLength() }
        return len
    }

    /// The rings as line strings, as GEOS 3.13 gives them (JTS 1.20 gives
    /// the rings themselves).
    override public func getBoundary() -> Geometry {
        if isEmpty() { return factory.createMultiLineString() }
        if holes.isEmpty { return factory.createLineString(shell.points) }
        return factory.createMultiLineString(([shell] + holes).map { factory.createLineString($0.points) })
    }

    override func computeEnvelopeInternal() -> Envelope { shell.getEnvelopeInternal() }

    override public func applyComponents(_ f: (Geometry) -> Void) {
        f(self)
        shell.applyComponents(f)
        for h in holes { h.applyComponents(f) }
    }

    override public func equalsExact(_ other: Geometry, tolerance: Double) -> Bool {
        guard isEquivalentClass(other), let o = other as? Polygon else { return false }
        if !shell.equalsExact(o.shell, tolerance: tolerance) { return false }
        if holes.count != o.holes.count { return false }
        for i in 0..<holes.count where !holes[i].equalsExact(o.holes[i], tolerance: tolerance) { return false }
        return true
    }

    override func copyInternal() -> Geometry {
        Polygon(shell: shell.copy() as? LinearRing, holes: holes.map { $0.copy() as! LinearRing }, factory: factory)
    }

    override public func convexHull() -> Geometry { getExteriorRing().convexHull() }

    override public func normalize() {
        shell = Polygon.normalizedRing(shell, clockwise: true)
        for i in 0..<holes.count { holes[i] = Polygon.normalizedRing(holes[i], clockwise: false) }
        // GEOS sorts the holes in descending order (JTS ascending).
        holes = javaSorted(holes) { $1.compareTo($0) }
    }

    override func compareToSameClass(_ other: Geometry) -> Int {
        let poly = other as! Polygon
        let shellComp = shell.compareToSameClass(poly.shell)
        if shellComp != 0 { return shellComp }
        let n1 = holes.count, n2 = poly.holes.count
        var i = 0
        while i < n1 && i < n2 {
            let c = holes[i].compareToSameClass(poly.holes[i])
            if c != 0 { return c }
            i += 1
        }
        if i < n1 { return 1 }
        if i < n2 { return -1 }
        return 0
    }

    /// A ring turned to start at its least point, clockwise or not: JTS's
    /// `normalize(ring)`, which keeps every point.
    static func normalized(_ ring: [Coordinate], clockwise: Bool) -> [Coordinate] {
        var seq = ring
        let minIndex = CoordinateSequences.minCoordinateIndex(seq, 0, seq.count - 2)
        CoordinateSequences.scroll(&seq, minIndex, ensureRing: true)
        if Orientation.isCCW(seq) == clockwise { seq.reverse() }
        return seq
    }

    /// A ring of a polygon normalized as GEOS 3.13 does: without its closing
    /// point, turned to start at its least point, closed again only if it
    /// does not already end there (so a repeated closing point goes), then
    /// clockwise or not.
    static func normalizedRing(_ ring: LinearRing, clockwise: Bool) -> LinearRing {
        let res = ring.copy() as! LinearRing
        if res.isEmpty() { return res }
        var seq = Array(res.points.dropLast())
        let minIndex = CoordinateSequences.minCoordinateIndex(seq, 0, seq.count - 1)
        if minIndex > 0 { seq = Array(seq[minIndex...] + seq[..<minIndex]) }
        if seq.first! != seq.last! { seq.append(seq[0]) }
        if Orientation.isCCW(seq) == clockwise { seq.reverse() }
        res.points = seq
        return res
    }

    override func reverseInternal() -> Geometry {
        factory.createPolygon(shell.reverse() as? LinearRing, holes.map { $0.reverse() as! LinearRing })
    }
}
