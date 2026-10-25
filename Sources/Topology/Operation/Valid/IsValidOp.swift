/// Whether a geometry is valid in the OGC sense, and the first error found:
/// JTS's `IsValidOp` (its implementation of 1.18 on, as GEOS 3.13's).
///
/// Throws where JTS and GEOS throw (a ring vertex expected on a ring that is
/// not on it, in a geometry of extreme coordinates), so `GEOSisValid`'s
/// failure is the port's error.
public final class IsValidOp {
    static let minSizeLineString = 2
    static let minSizeRing = 4

    public static func isValid(_ geom: Geometry) throws -> Bool { try IsValidOp(geom).isValid() }

    /// Whether both ordinates are finite.
    public static func isValid(_ coord: Coordinate) -> Bool { coord.x.isFinite && coord.y.isFinite }

    let inputGeometry: Geometry
    @exclusivity(unchecked) var isInvertedRingValid = false
    @exclusivity(unchecked) var validErr: TopologyValidationError?

    public init(_ inputGeometry: Geometry) {
        self.inputGeometry = inputGeometry
    }

    /// Whether a ring touching itself to form a hole is valid (the ESRI
    /// model); off by default, as in GEOS.
    public func setSelfTouchingRingFormingHoleValid(_ isValid: Bool) { isInvertedRingValid = isValid }

    public func isValid() throws -> Bool { try isValidGeometry(inputGeometry) }

    public func getValidationError() throws -> TopologyValidationError? {
        _ = try isValidGeometry(inputGeometry)
        return validErr
    }

    private func logInvalid(_ code: Int, _ pt: Coordinate?) { validErr = TopologyValidationError(code, pt) }
    private var hasInvalidError: Bool { validErr != nil }

    private func isValidGeometry(_ g: Geometry) throws -> Bool {
        validErr = nil
        // empty geometries are always valid
        if g.isEmpty() { return true }
        switch g {
        case let p as Point: return isValid(point: p)
        case let m as MultiPoint: return isValid(multiPoint: m)
        case let r as LinearRing: return isValid(ring: r)
        case let l as LineString: return isValid(line: l)
        case let p as Polygon: return try isValid(polygon: p)
        case let m as MultiPolygon: return try isValid(multiPolygon: m)
        case let c as GeometryCollection: return try isValid(collection: c)
        default: preconditionFailure(g.getGeometryType())
        }
    }

    private func isValid(point g: Point) -> Bool {
        checkCoordinatesValid(g.getCoordinates())
        return !hasInvalidError
    }

    /// GEOS checks each non-empty point (JTS its coordinates: the same).
    private func isValid(multiPoint g: MultiPoint) -> Bool {
        for p in g.geometries where !p.isEmpty() {
            let c = p.getCoordinate()!
            if !IsValidOp.isValid(c) {
                logInvalid(TopologyValidationError.invalidCoordinate, c)
                return false
            }
        }
        return true
    }

    private func isValid(line g: LineString) -> Bool {
        checkCoordinatesValid(g.points)
        if hasInvalidError { return false }
        checkPointSize(g, IsValidOp.minSizeLineString)
        return !hasInvalidError
    }

    private func isValid(ring g: LinearRing) -> Bool {
        checkCoordinatesValid(g.points)
        if hasInvalidError { return false }
        checkRingClosed(g)
        if hasInvalidError { return false }
        checkRingPointSize(g)
        if hasInvalidError { return false }
        checkRingSimple(g)
        return !hasInvalidError
    }

    private func isValid(polygon g: Polygon) throws -> Bool {
        checkCoordinatesValid(g)
        if hasInvalidError { return false }
        checkRingsClosed(g)
        if hasInvalidError { return false }
        checkRingsPointSize(g)
        if hasInvalidError { return false }
        let areaAnalyzer = PolygonTopologyAnalyzer(g, isInvertedRingValid)
        checkAreaIntersections(areaAnalyzer)
        if hasInvalidError { return false }
        try checkHolesInShell(g)
        if hasInvalidError { return false }
        try checkHolesNotNested(g)
        if hasInvalidError { return false }
        checkInteriorConnected(areaAnalyzer)
        return !hasInvalidError
    }

    private func isValid(multiPolygon g: MultiPolygon) throws -> Bool {
        let polys = g.geometries.map { $0 as! Polygon }
        for p in polys {
            checkCoordinatesValid(p)
            if hasInvalidError { return false }
            checkRingsClosed(p)
            if hasInvalidError { return false }
            checkRingsPointSize(p)
            if hasInvalidError { return false }
        }
        let areaAnalyzer = PolygonTopologyAnalyzer(g, isInvertedRingValid)
        checkAreaIntersections(areaAnalyzer)
        if hasInvalidError { return false }
        for p in polys {
            try checkHolesInShell(p)
            if hasInvalidError { return false }
        }
        for p in polys {
            try checkHolesNotNested(p)
            if hasInvalidError { return false }
        }
        try checkShellsNotNested(g)
        if hasInvalidError { return false }
        checkInteriorConnected(areaAnalyzer)
        return !hasInvalidError
    }

    private func isValid(collection gc: GeometryCollection) throws -> Bool {
        for g in gc.geometries where try !isValidGeometry(g) { return false }
        return true
    }

    private func checkCoordinatesValid(_ coords: [Coordinate]) {
        for c in coords where !IsValidOp.isValid(c) {
            logInvalid(TopologyValidationError.invalidCoordinate, c)
            return
        }
    }

    private func checkCoordinatesValid(_ poly: Polygon) {
        checkCoordinatesValid(poly.shell.points)
        if hasInvalidError { return }
        for h in poly.holes {
            checkCoordinatesValid(h.points)
            if hasInvalidError { return }
        }
    }

    private func checkRingClosed(_ ring: LinearRing) {
        if ring.isEmpty() { return }
        if !ring.isClosed() {
            logInvalid(TopologyValidationError.ringNotClosed, ring.getNumPoints() >= 1 ? ring.getCoordinateN(0) : nil)
        }
    }

    private func checkRingsClosed(_ poly: Polygon) {
        checkRingClosed(poly.shell)
        if hasInvalidError { return }
        for h in poly.holes {
            checkRingClosed(h)
            if hasInvalidError { return }
        }
    }

    private func checkRingsPointSize(_ poly: Polygon) {
        checkRingPointSize(poly.shell)
        if hasInvalidError { return }
        for h in poly.holes {
            checkRingPointSize(h)
            if hasInvalidError { return }
        }
    }

    private func checkRingPointSize(_ ring: LinearRing) {
        if ring.isEmpty() { return }
        checkPointSize(ring, IsValidOp.minSizeRing)
    }

    private func checkPointSize(_ line: LineString, _ minSize: Int) {
        if !IsValidOp.isNonRepeatedSizeAtLeast(line, minSize) {
            logInvalid(TopologyValidationError.tooFewPoints, line.getNumPoints() >= 1 ? line.getCoordinateN(0) : nil)
        }
    }

    private static func isNonRepeatedSizeAtLeast(_ line: LineString, _ minSize: Int) -> Bool {
        var numPts = 0
        var prevPt: Coordinate?
        for pt in line.points {
            if numPts >= minSize { return true }
            if prevPt == nil || !pt.equals2D(prevPt!) { numPts += 1 }
            prevPt = pt
        }
        return numPts >= minSize
    }

    private func checkAreaIntersections(_ areaAnalyzer: PolygonTopologyAnalyzer) {
        if areaAnalyzer.hasInvalidIntersection() {
            logInvalid(areaAnalyzer.getInvalidCode(), areaAnalyzer.getInvalidLocation())
        }
    }

    private func checkRingSimple(_ ring: LinearRing) {
        if let intPt = PolygonTopologyAnalyzer.findSelfIntersection(ring) {
            logInvalid(TopologyValidationError.ringSelfIntersection, intPt)
        }
    }

    private func checkHolesInShell(_ poly: Polygon) throws {
        // skip test if no holes are present
        if poly.getNumInteriorRing() <= 0 { return }
        let shell = poly.shell
        let isShellEmpty = shell.isEmpty()
        for hole in poly.holes {
            if hole.isEmpty() { continue }
            let invalidPt = isShellEmpty ? hole.getCoordinate() : try IsValidOp.findHoleOutsideShellPoint(hole, shell)
            if let invalidPt {
                logInvalid(TopologyValidationError.holeOutsideShell, invalidPt)
                return
            }
        }
    }

    private static func findHoleOutsideShellPoint(_ hole: LinearRing, _ shell: LinearRing) throws -> Coordinate? {
        let holePt0 = hole.getCoordinateN(0)
        // A hole whose envelope the shell's does not cover is outside it.
        if !shell.getEnvelopeInternal().covers(hole.getEnvelopeInternal()) { return holePt0 }
        if try PolygonTopologyAnalyzer.isRingNested(hole, shell) { return nil }
        return holePt0
    }

    private func checkHolesNotNested(_ poly: Polygon) throws {
        // skip test if no holes are present
        if poly.getNumInteriorRing() <= 0 { return }
        let nestedTester = IndexedNestedHoleTester(poly)
        if try nestedTester.isNested() {
            logInvalid(TopologyValidationError.nestedHoles, nestedTester.getNestedPoint())
        }
    }

    private func checkShellsNotNested(_ mp: MultiPolygon) throws {
        // skip test if only one shell present
        if mp.getNumGeometries() <= 1 { return }
        let nestedTester = IndexedNestedPolygonTester(mp)
        if try nestedTester.isNested() {
            logInvalid(TopologyValidationError.nestedShells, nestedTester.getNestedPoint())
        }
    }

    private func checkInteriorConnected(_ analyzer: PolygonTopologyAnalyzer) {
        if analyzer.isInteriorDisconnected() {
            logInvalid(TopologyValidationError.disconnectedInterior, analyzer.getDisconnectionLocation())
        }
    }
}

extension Geometry {
    /// Whether the geometry is valid (`GEOSisValid`).
    public func isValid() throws -> Bool { try IsValidOp(self).isValid() }
}
