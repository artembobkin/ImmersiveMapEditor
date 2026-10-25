/// Linear referencing by length along lineal geometry: JTS's
/// `LengthIndexedLine` with `LengthLocationMap`, `LengthIndexOfPoint`,
/// `LinearLocation` and `LinearIterator`, the part `GEOSInterpolate` and
/// `GEOSProject` run. A negative index counts from the end; an index past
/// the end gives the end point. As in GEOS, a component that is not a line
/// fails only when it is read, and the end location of a geometry with no
/// components is its start.
public struct LengthIndexedLine {
    let linearGeom: Geometry

    public init(_ linearGeom: Geometry) { self.linearGeom = linearGeom }

    /// The point at a length along the line (nil for an empty geometry).
    public func extractPoint(_ index: Double) throws -> Coordinate? {
        try LengthIndexedLine.getLocation(linearGeom, index).getCoordinate(linearGeom)
    }

    /// The length along the line of the point of the line nearest to `pt`.
    public func project(_ pt: Coordinate) throws -> Double { try LengthIndexedLine.indexOf(linearGeom, pt) }

    // MARK: LengthLocationMap

    static func getLocation(_ linearGeom: Geometry, _ length: Double) throws -> LinearLocation {
        var forwardLength = length
        if length < 0.0 { forwardLength = linearGeom.getLength() + length }
        return try getLocationForward(linearGeom, forwardLength)
    }

    private static func getLocationForward(_ linearGeom: Geometry, _ length: Double) throws -> LinearLocation {
        if length <= 0.0 { return LinearLocation() }
        var totalLength = 0.0
        var it = try LinearIterator(linearGeom)
        while it.hasNext() {
            // A length exactly at a component's end gives that end, not the
            // start of the next component, consistent with project.
            if it.isEndOfLine() {
                if totalLength == length { return LinearLocation(it.componentIndex, it.vertexIndex, 0.0) }
            } else {
                let p0 = it.getSegmentStart()
                let p1 = it.getSegmentEnd()
                let segLen = p1.distance(p0)
                // length falls in this segment
                if totalLength + segLen > length {
                    let frac = (length - totalLength) / segLen
                    return LinearLocation(it.componentIndex, it.vertexIndex, frac)
                }
                totalLength += segLen
            }
            try it.next()
        }
        return try LinearLocation.getEndLocation(linearGeom)
    }

    // MARK: LengthIndexOfPoint

    static func indexOf(_ linearGeom: Geometry, _ inputPt: Coordinate) throws -> Double {
        let minIndex = -1.0
        var minDistance = Double.infinity
        var ptMeasure = minIndex
        var segmentStartMeasure = 0.0
        var it = try LinearIterator(linearGeom)
        while it.hasNext() {
            if !it.isEndOfLine() {
                let seg = LineSegment(it.getSegmentStart(), it.getSegmentEnd())
                let segDistance = seg.distance(inputPt)
                let segMeasureToPt = segmentNearestMeasure(seg, inputPt, segmentStartMeasure)
                if segDistance < minDistance && segMeasureToPt > minIndex {
                    ptMeasure = segMeasureToPt
                    minDistance = segDistance
                }
                segmentStartMeasure += seg.getLength()
            }
            try it.next()
        }
        return ptMeasure
    }

    private static func segmentNearestMeasure(_ seg: LineSegment, _ inputPt: Coordinate, _ segmentStartMeasure: Double) -> Double {
        let projFactor = seg.projectionFactor(inputPt)
        if projFactor <= 0.0 { return segmentStartMeasure }
        if projFactor <= 1.0 { return fusedAdd(projFactor, seg.getLength(), segmentStartMeasure) }
        return segmentStartMeasure + seg.getLength()
    }
}

/// A place on lineal geometry: a component, a segment of it and a fraction
/// along the segment, JTS's `LinearLocation`.
struct LinearLocation {
    var componentIndex = 0
    var segmentIndex = 0
    var segmentFraction = 0.0

    init() {}

    /// A location, normalized: the fraction clamped to [0, 1], a fraction of
    /// 1 made the start of the next segment.
    init(_ componentIndex: Int, _ segmentIndex: Int, _ segmentFraction: Double) {
        self.componentIndex = componentIndex
        self.segmentIndex = segmentIndex
        self.segmentFraction = segmentFraction
        if self.segmentFraction < 0.0 { self.segmentFraction = 0.0 }
        if self.segmentFraction > 1.0 { self.segmentFraction = 1.0 }
        if self.segmentFraction == 1.0 {
            self.segmentFraction = 0.0
            self.segmentIndex += 1
        }
    }

    /// The end of the last component (not normalized).
    static func getEndLocation(_ linear: Geometry) throws -> LinearLocation {
        var loc = LinearLocation()
        let n = linear.getNumGeometries()
        if n == 0 { return loc }
        loc.componentIndex = n - 1
        guard let lastLine = linear.getGeometryN(loc.componentIndex) as? LineString else {
            throw IllegalArgumentException("LinearLocation::setToEnd only works with LineString geometries")
        }
        loc.segmentIndex = lastLine.getNumPoints() - 1
        loc.segmentFraction = 1.0
        return loc
    }

    /// The point of the location, nil on an empty geometry.
    func getCoordinate(_ linearGeom: Geometry) throws -> Coordinate? {
        if linearGeom.isEmpty() { return nil }
        guard let lineComp = linearGeom.getGeometryN(componentIndex) as? LineString else {
            throw IllegalArgumentException("LinearLocation::getCoordinate only works with LineString geometries")
        }
        let p0 = lineComp.getCoordinateN(segmentIndex)
        if segmentIndex >= lineComp.getNumPoints() - 1 { return p0 }
        let p1 = lineComp.getCoordinateN(segmentIndex + 1)
        return LinearLocation.pointAlongSegmentByFraction(p0, p1, segmentFraction)
    }

    static func pointAlongSegmentByFraction(_ p0: Coordinate, _ p1: Coordinate, _ frac: Double) -> Coordinate {
        if frac <= 0.0 { return p0 }
        if frac >= 1.0 { return p1 }
        return Coordinate(fusedAdd(p1.x - p0.x, frac, p0.x), fusedAdd(p1.y - p0.y, frac, p0.y))
    }
}

/// Walks the vertices of lineal geometry, component by component: JTS's
/// `LinearIterator`.
struct LinearIterator {
    let linear: Geometry
    let numLines: Int
    var currentLine: LineString?
    var componentIndex = 0
    var vertexIndex = 0

    init(_ linear: Geometry) throws {
        self.linear = linear
        numLines = linear.getNumGeometries()
        try loadCurrentLine()
    }

    private mutating func loadCurrentLine() throws {
        if componentIndex >= numLines {
            currentLine = nil
            return
        }
        guard let line = linear.getGeometryN(componentIndex) as? LineString else {
            throw IllegalArgumentException("LinearIterator only supports lineal geometry components")
        }
        currentLine = line
    }

    func hasNext() -> Bool {
        if componentIndex >= numLines { return false }
        if componentIndex == numLines - 1 && vertexIndex >= currentLine!.getNumPoints() { return false }
        return true
    }

    mutating func next() throws {
        if !hasNext() { return }
        vertexIndex += 1
        if vertexIndex >= currentLine!.getNumPoints() {
            componentIndex += 1
            try loadCurrentLine()
            vertexIndex = 0
        }
    }

    func isEndOfLine() -> Bool {
        if componentIndex >= numLines { return false }
        guard let currentLine else { return false }
        if vertexIndex < currentLine.getNumPoints() - 1 { return false }
        return true
    }

    func getSegmentStart() -> Coordinate { currentLine!.points[vertexIndex] }

    func getSegmentEnd() -> Coordinate {
        if vertexIndex < currentLine!.getNumPoints() - 1 { return currentLine!.points[vertexIndex + 1] }
        return .null
    }
}

extension Geometry {
    /// The point at a length along the line, from its end when negative
    /// (`GEOSInterpolate`), or at a share of its length
    /// (`GEOSInterpolateNormalized`).
    public func interpolate(_ d: Double, normalized: Bool = false) throws -> Point {
        let index = normalized ? d * getLength() : d
        let c = try LengthIndexedLine(self).extractPoint(index)
        // GEOS's C API makes an empty point of a null coordinate (NaN, NaN).
        return GeometryFactory.default.createPoint(c.flatMap { $0.isNull ? nil : $0 })
    }

    /// How far along the line the point nearest to a point is (`GEOSProject`).
    public func project(_ p: Geometry) throws -> Double {
        guard let point = p as? Point else { throw IllegalArgumentException("third argument of GEOSProject_r must be Point") }
        guard let c = point.getCoordinate() else { throw IllegalArgumentException("empty point") }
        return try LengthIndexedLine(self).project(c)
    }
}
