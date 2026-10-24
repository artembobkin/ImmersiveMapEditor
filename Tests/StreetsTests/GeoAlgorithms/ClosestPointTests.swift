/// The tests of geo 0.27's `closest_point.rs` (written for `f32` there, run in `f64` here: every
/// input and expected value is exact in both), and the point distance tests of
/// `euclidean_distance.rs`.

import GeoAlgorithms
import Testing

private func aSquare(_ width: Double) -> GeoLineString {
    geoLS([(0, 0), (width, 0), (width, width), (0, width), (0, 0)])
}

/// geo's `Translate`.
private func translate(_ l: GeoLineString, _ dx: Double, _ dy: Double) -> GeoLineString {
    l.mapCoords { geoC($0.x + dx, $0.y + dy) }
}

private func holyPolygon() -> GeoPolygon {
    GeoPolygon(aSquare(100), [translate(aSquare(20), 10, 10), translate(aSquare(10), 70, 60)])
}

@Suite struct ClosestPointTests {
    private let line = GeoLine(geoC(0, 0), geoC(100, 100))

    @Test func startPoint() { #expect(line.closestPoint(geoP(0, 0)) == .intersection(geoP(0, 0))) }
    @Test func endPoint() { #expect(line.closestPoint(geoP(100, 100)) == .intersection(geoP(100, 100))) }
    @Test func midPoint() { #expect(line.closestPoint(geoP(50, 50)) == .intersection(geoP(50, 50))) }
    @Test func inLineFarAway() { #expect(line.closestPoint(geoP(1000, 1000)) == .singlePoint(geoP(100, 100))) }
    @Test func perpendicularFrom5050() { #expect(line.closestPoint(geoP(0, 100)) == .singlePoint(geoP(50, 50))) }

    @Test func zeroLengthLineIsIndeterminate() {
        #expect(GeoLine(geoC(0, 0), geoC(0, 0)).closestPoint(geoP(100, 100)) == .indeterminate)
    }

    @Test func lineStringWithSingleElementBehavesLikeLine() {
        let lineString = geoLS([(0, 0), (100, 100)])
        let line = GeoLine(geoC(0, 0), geoC(100, 100))
        for q in [geoP(0, 0), geoP(100, 100), geoP(1000, 1000), geoP(100, 0), geoP(50, 50), geoP(1234.567, -987.6543)] {
            #expect(lineString.closestPoint(q) == line.closestPoint(q), "closest point to \(q)")
        }
    }

    @Test func emptyLineStringIsIndeterminate() {
        #expect(GeoLineString([]).closestPoint(geoP(0, 0)) == .indeterminate)
    }

    @Test func polygonWithoutRingsAndPointOutsideIsSameAsLinestring() {
        let polygon = holyPolygon()
        let q = geoP(1000, 12345.678)
        #expect(!polygon.exterior.contains(q), "`p` should be outside the polygon!")
        #expect(polygon.closestPoint(q) == polygon.exterior.closestPoint(q))
    }

    @Test func polygonWithPointOnInteriorRing() {
        let polygon = holyPolygon()
        let q = polygon.interiors[0].coords[3]
        #expect(polygon.closestPoint(GeoPoint(q)) == .intersection(GeoPoint(q)))
    }

    @Test func polygonWithPointNearInteriorRing() {
        let polygon = holyPolygon()
        let q = geoP(17, 33)
        #expect(polygon.intersects(q), "sanity check")
        #expect(polygon.closestPoint(q) == .intersection(q))
    }

    @Test func polygonWithInteriorPoint() {
        let square = geoPoly([(0, 0), (10, 0), (10, 10), (0, 10)])
        // The point is inside, so it is its own closest point.
        #expect(square.closestPoint(geoP(1, 2)) == .intersection(geoP(1, 2)))
    }

    @Test func multiPolygonWithInternalAndExternalPoints() {
        let square1 = geoPoly([(0, 0), (1, 0), (1, 1), (0, 1)])
        let square10 = square1.mapCoords { geoC($0.x + 10, $0.y + 10) }
        let square50 = square1.mapCoords { geoC($0.x + 50, $0.y + 50) }
        let multiPolygon = GeoMultiPolygon([square1, square10, square50])
        #expect(multiPolygon.closestPoint(geoP(8, 8)) == .singlePoint(geoP(10, 10)))
        #expect(multiPolygon.closestPoint(geoP(10.5, 10.5)) == .intersection(geoP(10.5, 10.5)))
    }
}

@Suite struct EuclideanDistanceTests {
    private let octagon: [(Double, Double)] = [(5, 1), (4, 2), (4, 3), (5, 4), (6, 4), (7, 3), (7, 2), (6, 1), (5, 1)]

    @Test func lineSegmentDistance() {
        let p1 = geoC(7.2, 2.0)
        let p2 = geoC(6.0, 1.0)
        let segment = GeoLine(p1, p2)
        // The results agree with Shapely.
        #expect(approxRelativeEq(segment.euclideanDistance(geoC(8.0, 0.0)), 2.0485900789263356))
        #expect(approxRelativeEq(segment.euclideanDistance(geoC(5.5, 0.0)), 1.118033988749895))
        #expect(approxRelativeEq(segment.euclideanDistance(geoC(5.0, 0.0)), 2.0.squareRoot()))
        #expect(approxRelativeEq(segment.euclideanDistance(geoC(4.5, 1.5)), 1.5811388300841898))
        // A point on the line.
        #expect(approxRelativeEq(segment.euclideanDistance(p1), 0.0))
    }

    @Test func pointPolygonDistanceOutside() {
        #expect(approxRelativeEq(geoP(2.5, 0.5).euclideanDistance(geoPoly(octagon)), 2.1213203435596424))
    }

    @Test func pointPolygonDistanceInside() {
        #expect(approxRelativeEq(geoP(5.5, 2.1).euclideanDistance(geoPoly(octagon)), 0.0))
    }

    @Test func pointPolygonDistanceBoundary() {
        #expect(approxRelativeEq(geoP(5.0, 1.0).euclideanDistance(geoPoly(octagon)), 0.0))
    }

    @Test func pointPolygonBoundary2() {
        let polygon = geoPoly([(0, 0), (0, 0.0004), (0.0004, 0.0004), (0.0004, 0), (0, 0)])
        #expect(approxRelativeEq(polygon.euclideanDistance(geoP(0.0001, 0)), 0))
    }

    @Test func pointPolygonEmpty() {
        #expect(approxRelativeEq(geoP(2.5, 0.5).euclideanDistance(GeoPolygon(GeoLineString([]), [])), 0.0))
    }

    @Test func pointPolygonInteriorCutout() {
        let polygon = geoPoly([(4, 1), (5, 2), (5, 3), (4, 4), (3, 4), (2, 3), (2, 2), (3, 1), (4, 1)],
                           [[(3.5, 3.5), (4.4, 1.5), (2.6, 1.5), (3.5, 3.5)]])
        // Shapely gives 0.41036467732879783.
        #expect(approxRelativeEq(geoP(3.5, 2.5).euclideanDistance(polygon), 0.41036467732879767))
    }

    @Test func pointLinestringDistance() {
        // An octagon without its lowest horizontal side.
        let lineString = geoLS(Array(octagon.dropLast()))
        #expect(approxRelativeEq(geoP(5.5, 2.1).euclideanDistance(lineString), 1.1313708498984762))
    }

    @Test func pointLinestringContains() {
        let lineString = geoLS(Array(octagon.dropLast()))
        #expect(approxRelativeEq(geoP(5.0, 4.0).euclideanDistance(lineString), 0.0))
    }

    @Test func pointLinestringTriangle() {
        let lineString = geoLS([(3.5, 3.5), (4.4, 2.0), (2.6, 2.0), (3.5, 3.5)])
        #expect(approxRelativeEq(geoP(3.5, 2.5).euclideanDistance(lineString), 0.5))
    }

    @Test func pointLinestringEmpty() {
        #expect(approxRelativeEq(geoP(5.0, 4.0).euclideanDistance(GeoLineString([])), 0.0))
    }

    @Test func distance1() {
        #expect(approxRelativeEq(geoP(0, 0).euclideanDistance(geoP(1, 0)), 1))
    }

    @Test func distance2() {
        #expect(approxRelativeEq(geoP(-72.1235, 42.3521).euclideanDistance(geoP(72.1260, 70.612)), 146.99163308930207))
    }

    @Test func distanceLine() {
        let line0 = GeoLine(geoC(0, 0), geoC(5, 0))
        #expect(approxRelativeEq(line0.euclideanDistance(geoP(2, 3)), 3))
        #expect(approxRelativeEq(geoP(2, 3).euclideanDistance(line0), 3))
        #expect(approxRelativeEq(line0.euclideanDistance(geoP(3, 0)), 0))
        #expect(approxRelativeEq(geoP(3, 0).euclideanDistance(line0), 0))
        #expect(approxRelativeEq(line0.euclideanDistance(geoP(6, 0)), 1))
        #expect(approxRelativeEq(geoP(6, 0).euclideanDistance(line0), 1))
    }
}
