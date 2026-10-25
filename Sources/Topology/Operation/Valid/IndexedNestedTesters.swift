/// Whether any hole of a polygon is nested inside another: JTS's
/// `IndexedNestedHoleTester`, the holes in an STR tree.
final class IndexedNestedHoleTester {
    let polygon: Polygon
    let index = STRtree<LinearRing>()
    @exclusivity(unchecked) private(set) var nestedPt: Coordinate?

    init(_ poly: Polygon) {
        polygon = poly
        for hole in poly.holes { index.insert(hole.getEnvelopeInternal(), hole) }
    }

    func getNestedPoint() -> Coordinate? { nestedPt }

    func isNested() throws -> Bool {
        for hole in polygon.holes {
            for testHole in index.query(hole.getEnvelopeInternal()) {
                if hole === testHole { continue }
                // A hole not covered by the test hole's envelope cannot be nested in it.
                if !testHole.getEnvelopeInternal().covers(hole.getEnvelopeInternal()) { continue }
                if try PolygonTopologyAnalyzer.isRingNested(hole, testHole) {
                    nestedPt = hole.getCoordinateN(0)
                    return true
                }
            }
        }
        return false
    }
}

/// Whether any polygon of a multipolygon is nested inside another: JTS's
/// `IndexedNestedPolygonTester`, the polygons in an STR tree, each outer
/// candidate with an indexed point locator made when first needed.
final class IndexedNestedPolygonTester {
    let multiPoly: MultiPolygon
    let index = STRtree<Int>()
    @exclusivity(unchecked) var locators: [IndexedPointInAreaLocator?]
    @exclusivity(unchecked) private(set) var nestedPt: Coordinate?

    init(_ multiPoly: MultiPolygon) {
        self.multiPoly = multiPoly
        locators = Array(repeating: nil, count: multiPoly.getNumGeometries())
        for i in 0..<multiPoly.getNumGeometries() { index.insert(multiPoly.getGeometryN(i).getEnvelopeInternal(), i) }
    }

    func getLocator(_ polyIndex: Int) -> IndexedPointInAreaLocator {
        if let l = locators[polyIndex] { return l }
        let l = IndexedPointInAreaLocator(multiPoly.getGeometryN(polyIndex))
        locators[polyIndex] = l
        return l
    }

    func getNestedPoint() -> Coordinate? { nestedPt }

    func isNested() throws -> Bool {
        for i in 0..<multiPoly.getNumGeometries() {
            let poly = multiPoly.getGeometryN(i) as! Polygon
            let shell = poly.getExteriorRing()
            for polyIndex in index.query(poly.getEnvelopeInternal()) {
                let possibleOuterPoly = multiPoly.getGeometryN(polyIndex) as! Polygon
                if poly === possibleOuterPoly { continue }
                // A polygon not covered by the candidate's envelope cannot be nested in it.
                if !possibleOuterPoly.getEnvelopeInternal().covers(poly.getEnvelopeInternal()) { continue }
                nestedPt = try findNestedPoint(shell, possibleOuterPoly, getLocator(polyIndex))
                if nestedPt != nil { return true }
            }
        }
        return false
    }

    private func findNestedPoint(_ shell: LinearRing, _ possibleOuterPoly: Polygon, _ locator: IndexedPointInAreaLocator) throws -> Coordinate? {
        // Two points are tried first, since locating a point is fast.
        let shellPt0 = shell.getCoordinateN(0)
        let loc0 = locator.locate(shellPt0)
        if loc0 == Location.exterior { return nil }
        if loc0 == Location.interior { return shellPt0 }
        let shellPt1 = shell.getCoordinateN(1)
        let loc1 = locator.locate(shellPt1)
        if loc1 == Location.exterior { return nil }
        if loc1 == Location.interior { return shellPt1 }
        // Both lie on the boundary of the polygon: the topology of the
        // incident edges decides.
        return try IndexedNestedPolygonTester.findIncidentSegmentNestedPoint(shell, possibleOuterPoly)
    }

    /// A point of a shell inside a polygon, if the shell (which touches the
    /// polygon only at vertices and does not cross it) is inside it and not
    /// inside one of its holes.
    private static func findIncidentSegmentNestedPoint(_ shell: LinearRing, _ poly: Polygon) throws -> Coordinate? {
        let polyShell = poly.getExteriorRing()
        if polyShell.isEmpty() { return nil }
        if try !PolygonTopologyAnalyzer.isRingNested(shell, polyShell) { return nil }
        // A shell inside a hole is valid.
        for hole in poly.holes where hole.getEnvelopeInternal().covers(shell.getEnvelopeInternal()) {
            if try PolygonTopologyAnalyzer.isRingNested(shell, hole) { return nil }
        }
        // Inside the polygon and not in a hole: invalid.
        return shell.getCoordinateN(0)
    }
}
