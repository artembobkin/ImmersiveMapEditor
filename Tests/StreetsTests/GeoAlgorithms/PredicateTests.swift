/// The tests of geo 0.27's `coordinate_position.rs` and of the point and line string cases of
/// `contains/mod.rs`. Tests through `Relate`, geometry collections and integer scalars are not
/// ported, as those parts are not.

import GeoAlgorithms
import Testing

@Suite struct CoordinatePositionTests {
    @Test func emptyPoly() {
        let squarePoly = GeoPolygon(GeoLineString([]), [])
        #expect(squarePoly.coordinatePosition(.zero) == .outside)
    }

    @Test func simplePoly() {
        let squarePoly = geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)])
        #expect(squarePoly.coordinatePosition(geoC(1, 1)) == .inside)
        #expect(squarePoly.coordinatePosition(geoC(0, 0)) == .onBoundary)
        #expect(squarePoly.coordinatePosition(geoC(0, 1)) == .onBoundary)
        #expect(squarePoly.coordinatePosition(geoC(5, 5)) == .outside)
    }

    @Test func polyInterior() {
        let polygon = geoPoly([(11, 11), (20, 11), (20, 20), (11, 20), (11, 11)],
                           [[(13, 13), (13, 17), (17, 17), (17, 13), (13, 13)]])
        #expect(polygon.coordinatePosition(geoC(14, 14)) == .outside)
        #expect(polygon.coordinatePosition(geoC(30, 30)) == .outside)
        #expect(polygon.coordinatePosition(geoC(20, 15)) == .onBoundary)
        #expect(polygon.coordinatePosition(geoC(13, 15)) == .onBoundary)
        #expect(polygon.coordinatePosition(geoC(12, 12)) == .inside)
    }

    @Test func simpleLine() {
        let line = GeoLine(geoC(0, 0), geoC(10, 10))
        #expect(line.coordinatePosition(geoC(0, 0)) == .onBoundary)
        #expect(line.coordinatePosition(geoC(10, 10)) == .onBoundary)
        #expect(line.coordinatePosition(geoC(5, 5)) == .inside)
        #expect(line.coordinatePosition(geoC(6, 5)) == .outside)
    }

    @Test func degenerateLine() {
        let line = GeoLine(geoC(0, 0), geoC(0, 0))
        #expect(line.coordinatePosition(geoC(0, 0)) == .inside)
        #expect(line.coordinatePosition(geoC(10, 10)) == .outside)
    }

    @Test func point() {
        let p1 = geoP(2, 0)
        let c1 = geoC(2, 0)
        let c2 = geoC(3, 3)
        #expect(p1.coordinatePosition(c1) == .inside)
        #expect(p1.coordinatePosition(c2) == .outside)
        #expect(c1.coordinatePosition(c1) == .inside)
        #expect(c1.coordinatePosition(c2) == .outside)
    }

    @Test func simpleLineString() {
        let lineString = geoLS([(0, 0), (1, 1), (2, 0), (3, 0)])
        #expect(lineString.coordinatePosition(.zero) == .onBoundary)
        #expect(lineString.coordinatePosition(geoC(0.5, 0.5)) == .inside)
        #expect(lineString.coordinatePosition(geoC(2, 0)) == .inside)
        #expect(lineString.coordinatePosition(geoC(3, 0)) == .onBoundary)
        #expect(lineString.coordinatePosition(geoC(3, 1)) == .outside)
    }

    @Test func degenerateLineStrings() {
        #expect(geoLS([(0, 0), (0, 0)]).coordinatePosition(.zero) == .inside)
        #expect(geoLS([(0, 0), (2, 0)]).coordinatePosition(.zero) == .onBoundary)
    }

    @Test func closedLineString() {
        let lineString = geoLS([(0, 0), (1, 1), (2, 0), (3, 2), (0, 2), (0, 0)])
        #expect(lineString.isClosed)
        // Closed line strings have no boundary.
        #expect(lineString.coordinatePosition(.zero) == .inside)
        #expect(lineString.coordinatePosition(geoC(0.5, 0.5)) == .inside)
        #expect(lineString.coordinatePosition(geoC(3, 1)) == .outside)
    }

    @Test func boundaryRule() {
        let multiLineString = GeoMultiLineString([
            // The first two share a start point but not an end point.
            geoLS([(0, 0), (1, 1)]),
            geoLS([(0, 0), (-1, -1)]),
            // The third ends in the middle of the first.
            geoLS([(0, 1), (0.5, 0.5)]),
            // The fourth and fifth both end in the middle of the second.
            geoLS([(0, -1), (-0.5, -0.5)]),
            geoLS([(0, -2), (-0.5, -0.5)]),
        ])
        #expect(multiLineString.coordinatePosition(geoC(123, 123)) == .outside)
        #expect(multiLineString.coordinatePosition(geoC(-1, -1)) == .onBoundary)
        // On the boundary of two lines, so not on the boundary by the mod 2 rule.
        #expect(multiLineString.coordinatePosition(.zero) == .outside)
        #expect(multiLineString.coordinatePosition(geoC(0.5, 0.5)) == .onBoundary)
        #expect(multiLineString.coordinatePosition(geoC(-0.5, -0.5)) == .inside)
    }

    @Test func rect() {
        let rect = GeoRect(geoC(0, 0), geoC(10, 10))
        #expect(rect.coordinatePosition(geoC(5, 5)) == .inside)
        #expect(rect.coordinatePosition(geoC(0, 5)) == .onBoundary)
        #expect(rect.coordinatePosition(geoC(15, 15)) == .outside)
    }

    @Test func triangle() {
        let triangle = GeoTriangle(geoC(0, 0), geoC(5, 10), geoC(10, 0))
        #expect(triangle.coordinatePosition(geoC(5, 5)) == .inside)
        #expect(triangle.coordinatePosition(geoC(2.5, 5)) == .onBoundary)
        #expect(triangle.coordinatePosition(geoC(2.49, 5)) == .outside)
    }
}

@Suite struct ContainsTests {
    @Test func linestringContainsPoint() {
        #expect(geoLS([(0, 0), (3, 3)]).contains(geoP(1, 1)))
    }

    @Test func emptyLinestring() {
        #expect(!GeoLineString([]).contains(geoP(2, 1)))
    }

    @Test func linestringPointIsVertex() {
        let linestring = geoLS([(0, 0), (2, 0), (2, 2)])
        // The end points of a line string are not contained.
        #expect(linestring.contains(geoP(2, 0)))
        #expect(!linestring.contains(geoP(0, 0)))
        #expect(!linestring.contains(geoP(2, 2)))
    }

    @Test func linestring() {
        #expect(geoLS([(0, 0), (2, 0), (2, 2)]).contains(geoP(1, 0)))
    }

    @Test func emptyPolygon() {
        #expect(!GeoPolygon(GeoLineString([]), []).contains(geoP(2, 1)))
    }

    @Test func polygonWithOnePoint() {
        #expect(!GeoPolygon(geoLS([(2, 1)]), []).contains(geoP(3, 1)))
    }

    @Test func polygonWithOnePointIsVertex() {
        #expect(!GeoPolygon(geoLS([(2, 1)]), []).contains(geoP(2, 1)))
    }

    @Test func polygonWithPointOnBoundary() {
        let polygon = geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)])
        #expect(!polygon.contains(geoP(1, 0)))
        #expect(!polygon.contains(geoP(2, 1)))
        #expect(!polygon.contains(geoP(1, 2)))
        #expect(!polygon.contains(geoP(0, 1)))
    }

    @Test func pointInPolygon() {
        #expect(geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)]).contains(geoP(1, 1)))
    }

    @Test func pointInPolygonWithRayPassingThroughAVertex() {
        #expect(geoPoly([(1, 0), (0, 1), (-1, 0), (0, -1)]).contains(geoP(0, 0)))
    }

    @Test func pointInPolygonWithRayPassingThroughAVertexAndNotCrossing() {
        #expect(geoPoly([(0, 0), (2, 0), (3, 1), (4, 0), (4, 2), (0, 2), (0, 0)]).contains(geoP(1, 1)))
    }

    @Test func pointOutPolygon() {
        let polygon = geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)])
        #expect(!polygon.contains(geoP(2.1, 1)))
        #expect(!polygon.contains(geoP(1, 2.1)))
        #expect(!polygon.contains(geoP(2.1, 2.1)))
    }

    @Test func pointPolygonWithInner() {
        let polygon = geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)],
                           [[(0.5, 0.5), (1.5, 0.5), (1.5, 1.5), (0.0, 1.5), (0.0, 0.0)]])
        #expect(!polygon.contains(geoP(0.25, 0.25)))
        #expect(!polygon.contains(geoP(1, 1)))
        #expect(!polygon.contains(geoP(1.5, 1.5)))
        #expect(!polygon.contains(geoP(1.5, 1)))
    }

    @Test func emptyMultipolygon() {
        #expect(!GeoMultiPolygon([GeoPolygon]()).contains(geoP(2, 1)))
    }

    @Test func multipolygonTwoPolygons() {
        let multipoly = GeoMultiPolygon([
            geoPoly([(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)]),
            geoPoly([(2, 0), (3, 0), (3, 1), (2, 1), (2, 0)]),
        ])
        #expect(multipoly.contains(geoP(0.5, 0.5)))
        #expect(multipoly.contains(geoP(2.5, 0.5)))
        #expect(!multipoly.contains(geoP(1.5, 0.5)))
    }

    @Test func multipolygonTwoPolygonsAndInner() {
        let multipoly = GeoMultiPolygon([
            geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)], [[(1, 1), (4, 1), (4, 4), (1, 1)]]),
            geoPoly([(9, 0), (14, 0), (14, 4), (9, 4), (9, 0)]),
        ])
        #expect(multipoly.contains(geoP(3, 5)))
        #expect(multipoly.contains(geoP(12, 2)))
        #expect(!multipoly.contains(geoP(3, 2)))
        #expect(!multipoly.contains(geoP(7, 2)))
    }

    @Test func pointInLine() {
        let p0 = geoC(2, 4)
        // A vertical line.
        let line1 = GeoLine(geoC(2, 0), geoC(2, 5))
        // On the line's extension, outside the segment.
        let line2 = GeoLine(geoC(0, 6), geoC(1.5, 4.5))
        // On the line.
        let line3 = GeoLine(geoC(0, 6), geoC(3, 3))
        #expect(line1.contains(GeoPoint(p0)))
        #expect(!line2.contains(GeoPoint(p0)))
        #expect(line3.contains(GeoPoint(p0)))
    }
}
