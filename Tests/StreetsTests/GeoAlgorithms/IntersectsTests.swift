/// The tests of geo 0.27's `intersects/mod.rs` for the pairs ported here (line strings, lines,
/// points, rectangles and polygons).

import GeoAlgorithms
import Testing

@Suite struct IntersectsTests {
    @Test func emptyLinestring1() {
        #expect(!GeoLineString([]).intersects(geoLS([(3, 2), (7, 6)])))
    }

    @Test func emptyLinestring2() {
        #expect(!geoLS([(3, 2), (7, 6)]).intersects(GeoLineString([])))
    }

    @Test func emptyAllLinestring() {
        #expect(!GeoLineString([]).intersects(GeoLineString([])))
    }

    @Test func intersectLinestring() {
        #expect(geoLS([(3, 2), (7, 6)]).intersects(geoLS([(3, 4), (8, 4)])))
    }

    @Test func parallelLinestrings() {
        #expect(!geoLS([(3, 2), (7, 6)]).intersects(geoLS([(3, 1), (7, 5)])))
    }

    @Test func linestringInPolygon() {
        let polygon = geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)])
        #expect(polygon.intersects(geoLS([(2, 2), (3, 3)])))
    }

    @Test func linestringOnBoundaryPolygon() {
        let polygon = geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)])
        #expect(polygon.intersects(geoLS([(0, 0), (5, 0)])))
        #expect(polygon.intersects(geoLS([(5, 0), (5, 6)])))
        #expect(polygon.intersects(geoLS([(5, 6), (0, 6)])))
        #expect(polygon.intersects(geoLS([(0, 6), (0, 0)])))
    }

    @Test func intersectLinestringPolygon() {
        #expect(geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)]).intersects(geoLS([(2, 2), (6, 6)])))
    }

    @Test func linestringOutsidePolygon() {
        #expect(!geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)]).intersects(geoLS([(7, 2), (9, 4)])))
    }

    @Test func linestringInInnerPolygon() {
        let polygon = geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)], [[(1, 1), (4, 1), (4, 4), (1, 4), (1, 1)]])
        #expect(!polygon.intersects(geoLS([(2, 2), (3, 3)])))
        #expect(polygon.intersects(geoLS([(2, 2), (4, 4)])))
    }

    @Test func linestringTraversePolygon() {
        let polygon = geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)], [[(1, 1), (4, 1), (4, 4), (1, 4), (1, 1)]])
        #expect(polygon.intersects(geoLS([(2, 0.5), (2, 5)])))
    }

    @Test func linestringInInnerWith2InnerPolygon() {
        let polygon = geoPoly([(2, 2), (14, 2), (14, 8), (2, 8), (2, 2)], [
            [(4, 3), (7, 3), (7, 6), (4, 6), (4, 3)],
            [(9, 3), (12, 3), (12, 6), (9, 6), (9, 3)],
        ])
        #expect(!polygon.intersects(geoLS([(5, 4), (6, 5)])))
        #expect(polygon.intersects(geoLS([(11, 2.5), (11, 7)])))
        #expect(polygon.intersects(geoLS([(4, 7), (6, 7)])))
        #expect(polygon.intersects(geoLS([(8, 1), (8, 9)])))
    }

    @Test func polygonsDoNotIntersect() {
        let p1 = geoPoly([(1, 3), (3, 3), (3, 5), (1, 5), (1, 3)])
        let p2 = geoPoly([(10, 30), (30, 30), (30, 50), (10, 50), (10, 30)])
        #expect(!p1.intersects(p2))
        #expect(!p2.intersects(p1))
    }

    @Test func polygonsOverlap() {
        let p1 = geoPoly([(1, 3), (3, 3), (3, 5), (1, 5), (1, 3)])
        let p2 = geoPoly([(2, 3), (4, 3), (4, 7), (2, 7), (2, 3)])
        #expect(p1.intersects(p2))
        #expect(p2.intersects(p1))
    }

    @Test func polygonContained() {
        let p1 = geoPoly([(1, 3), (4, 3), (4, 6), (1, 6), (1, 3)])
        let p2 = geoPoly([(2, 4), (3, 4), (3, 5), (2, 5), (2, 4)])
        #expect(p1.intersects(p2))
        #expect(p2.intersects(p1))
    }

    @Test func polygonsConincident() {
        let p1 = geoPoly([(1, 3), (4, 3), (4, 6), (1, 6), (1, 3)])
        let p2 = geoPoly([(1, 3), (4, 3), (4, 6), (1, 6), (1, 3)])
        #expect(p1.intersects(p2))
        #expect(p2.intersects(p1))
    }

    @Test func polygonIntersectsBoundingRect() {
        let polygon = geoPoly([(0, 0), (12, 0), (12, 8), (0, 8), (0, 0)], [[(7, 4), (11, 4), (11, 7), (7, 7), (7, 4)]])
        let b1 = GeoRect(geoC(11, 1), geoC(13, 2))
        let b2 = GeoRect(geoC(2, 2), geoC(8, 5))
        let b3 = GeoRect(geoC(8, 5), geoC(10, 6))
        let b4 = GeoRect(geoC(1, 1), geoC(3, 3))
        #expect(polygon.intersects(b1))
        #expect(polygon.intersects(b2))
        #expect(!polygon.intersects(b3))
        #expect(polygon.intersects(b4))
        #expect(b1.intersects(polygon))
        #expect(b2.intersects(polygon))
        #expect(!b3.intersects(polygon))
        #expect(b4.intersects(polygon))
    }

    @Test func boundingRect() {
        let xl = GeoRect(geoC(-100, -200), geoC(100, 200))
        let sm = GeoRect(geoC(-10, -20), geoC(10, 20))
        let s2 = GeoRect(geoC(0, 0), geoC(20, 30))
        #expect(xl.intersects(sm))
        #expect(sm.intersects(xl))
        #expect(sm.intersects(s2))
        #expect(s2.intersects(sm))
    }

    @Test func rectIntersectionConsistentWithPolyIntersection() {
        let xl = GeoRect(geoC(-100, -200), geoC(100, 200))
        let sm = GeoRect(geoC(-10, -20), geoC(10, 20))
        let s2 = GeoRect(geoC(0, 0), geoC(20, 30))
        for (a, b) in [(xl, sm), (sm, xl), (sm, s2), (s2, sm)] {
            #expect(a.toPolygon().intersects(b))
            #expect(a.intersects(b.toPolygon()))
            #expect(a.toPolygon().intersects(b.toPolygon()))
        }
    }

    @Test func pointIntersectsLine() {
        let p0 = geoP(2, 4)
        let lines: [(GeoLine, Bool)] = [
            (GeoLine(geoC(2, 0), geoC(2, 5)), true),   // vertical
            (GeoLine(geoC(0, 6), geoC(1.5, 4.5)), false), // on the extension
            (GeoLine(geoC(0, 6), geoC(3, 3)), true),   // on the line
            (GeoLine(geoC(1, 2), geoC(5, 3)), false),  // above, positive slope
            (GeoLine(geoC(1, 5), geoC(5, 6)), false),  // below, positive slope
            (GeoLine(geoC(1, 2), geoC(5, -3)), false), // above, negative slope
            (GeoLine(geoC(1, 6), geoC(5, 5)), false),  // below, negative slope
        ]
        for (line, expected) in lines {
            #expect(line.intersects(p0) == expected)
            #expect(p0.intersects(line) == expected)
        }
    }

    @Test func lineIntersectsLine() {
        let line0 = GeoLine(geoC(0, 0), geoC(3, 4))
        let line1 = GeoLine(geoC(2, 0), geoC(2, 5))
        let line2 = GeoLine(geoC(0, 7), geoC(5, 4))
        let line3 = GeoLine(geoC(0, 0), geoC(-3, -4))
        #expect(line0.intersects(line0))
        #expect(line0.intersects(line1))
        #expect(!line0.intersects(line2))
        #expect(line0.intersects(line3))

        #expect(line1.intersects(line0))
        #expect(line1.intersects(line1))
        #expect(!line1.intersects(line2))
        #expect(!line1.intersects(line3))

        #expect(!line2.intersects(line0))
        #expect(!line2.intersects(line1))
        #expect(line2.intersects(line2))
        #expect(!line1.intersects(line3))
    }

    @Test func lineIntersectsLinestring() {
        let line0 = GeoLine(geoC(0, 0), geoC(3, 4))
        let linestring0 = geoLS([(0, 1), (1, 0), (2, 0)])
        let linestring1 = geoLS([(0.5, 0.2), (1, 0), (2, 0)])
        #expect(line0.intersects(linestring0))
        #expect(!line0.intersects(linestring1))
        #expect(linestring0.intersects(line0))
        #expect(!linestring1.intersects(line0))
    }

    @Test func lineIntersectsPolygon() {
        let line0 = GeoLine(geoC(0.5, 0.5), geoC(2, 1))
        let poly0 = geoPoly([(0, 0), (1, 2), (1, 0), (0, 0)])
        let poly1 = geoPoly([(1, -1), (2, -1), (2, -2), (1, -1)])
        // The line lies in the hole.
        let poly2 = geoPoly([(-1, -1), (-1, 10), (10, -1), (-1, -1)], [[(0, 0), (3, 4), (3, 0), (0, 0)]])
        #expect(line0.intersects(poly0))
        #expect(poly0.intersects(line0))
        #expect(!line0.intersects(poly1))
        #expect(!poly1.intersects(line0))
        #expect(!line0.intersects(poly2))
        #expect(!poly2.intersects(line0))
    }

    @Test func rect419() {
        let a = GeoRect(geoC(9.228515625, 46.83013364044739), geoC(9.2724609375, 46.86019101567026))
        let b = GeoRect(geoC(9.17953, 46.82018), geoC(9.26309, 46.88099))
        #expect(a.intersects(b))
        #expect(b.intersects(a))
    }
}
