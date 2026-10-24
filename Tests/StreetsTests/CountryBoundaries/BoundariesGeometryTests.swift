/// Tests of the multipolygon and cell lookups, ported from the inline tests of
/// `multipolygon.rs` and `cell.rs` of country-boundaries 1.2.0.

import Testing
@testable import CountryBoundaries

private func p(_ x: UInt16, _ y: UInt16) -> Point {
    Point(x: x, y: y)
}

@Suite struct BoundariesMultipolygonTests {
    private let bigSquare = [p(0, 0), p(0, 10), p(10, 10), p(10, 0)]
    private let hole = [p(2, 2), p(2, 8), p(8, 8), p(8, 2)]
    private let smallSquare = [p(4, 4), p(4, 6), p(6, 6), p(6, 4)]

    @Test func simplePointInPolygon() {
        #expect(isPointInPolygon(p(5, 5), bigSquare))
    }

    @Test func coversSimplePolygon() {
        #expect(Multipolygon(outer: [bigSquare], inner: []).covers(p(5, 5)))
    }

    @Test func doesNotCoverHole() {
        #expect(!Multipolygon(outer: [bigSquare], inner: [hole]).covers(p(5, 5)))
    }

    @Test func doesCoverPolygonInHole() {
        #expect(Multipolygon(outer: [bigSquare, smallSquare], inner: [hole]).covers(p(5, 5)))
    }

    @Test func onlyUpperLeftEdgeCountsAsInside() {
        let polygon = Multipolygon(outer: [bigSquare], inner: [])
        #expect(polygon.covers(p(0, 0)))
        #expect(polygon.covers(p(5, 0)))
        #expect(polygon.covers(p(0, 5)))
        #expect(!polygon.covers(p(0, 10)))
        #expect(!polygon.covers(p(10, 0)))
        #expect(!polygon.covers(p(5, 10)))
        #expect(!polygon.covers(p(10, 5)))
        #expect(!polygon.covers(p(10, 10)))
    }
}

@Suite struct BoundariesCellTests {
    private let b = IntersectingArea(
        id: "B",
        multipolygon: Multipolygon(outer: [[p(0, 0), p(0, 2), p(2, 2), p(2, 0)]], inner: [])
    )

    @Test func getDefiniteIds() {
        #expect(Cell(containingIds: ["A", "C"], intersectingAreas: []).getIds(p(0, 0)) == ["A", "C"])
    }

    @Test func getInGeometryIds() {
        #expect(Cell(containingIds: [], intersectingAreas: [b]).getIds(p(1, 1)) == ["B"])
    }

    @Test func dontGetOutOfGeometryIds() {
        #expect(Cell(containingIds: [], intersectingAreas: [b]).getIds(p(4, 4)).isEmpty)
    }

    @Test func getDefiniteAndInGeometryIds() {
        #expect(Cell(containingIds: ["A"], intersectingAreas: [b]).getIds(p(1, 1)) == ["B", "A"])
    }

    @Test func getAllIds() {
        #expect(Cell(containingIds: ["A"], intersectingAreas: [b]).getAllIds() == ["A", "B"])
    }

    @Test func isInAnyDefinitely() {
        #expect(Cell(containingIds: ["A"], intersectingAreas: []).isInAny(p(0, 0), ["B", "A"]))
    }

    @Test func isInAnyDefinitelyNot() {
        #expect(!Cell(containingIds: ["A"], intersectingAreas: []).isInAny(p(0, 0), ["B"]))
    }

    @Test func isInAnyInGeometry() {
        #expect(Cell(containingIds: [], intersectingAreas: [b]).isInAny(p(1, 1), ["B"]))
    }

    @Test func isInAnyOutOfGeometry() {
        #expect(!Cell(containingIds: [], intersectingAreas: [b]).isInAny(p(4, 4), ["B"]))
    }
}
