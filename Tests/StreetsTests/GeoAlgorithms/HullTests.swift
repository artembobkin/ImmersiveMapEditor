/// The tests of geo 0.27's `convex_hull/test.rs`, `convex_hull/qhull.rs` and `is_convex.rs`
/// (integer inputs run as `f64`, which holds them exactly). The tests over geo-test-fixtures are
/// skipped: the crate is not in the cargo registry.

@testable import GeoAlgorithms
import Testing

private func coords(_ pairs: [(Double, Double)]) -> [GeoCoord] {
    pairs.map { geoC($0.0, $0.1) }
}

@Suite struct TrivialHullTests {
    @Test func zeroPoints() {
        #expect(trivialHull([], includeOnHull: false).coords == [])
        #expect(trivialHull([], includeOnHull: true).coords == [])
    }

    @Test func onePoint() {
        let correct = coords([(0, 0), (0, 0)])
        #expect(trivialHull(coords([(0, 0)]), includeOnHull: false).coords == correct)
        #expect(trivialHull(coords([(0, 0)]), includeOnHull: true).coords == correct)
    }

    @Test func twoPoints() {
        let correct = coords([(0, 0), (1, 1), (0, 0)])
        #expect(trivialHull(coords([(0, 0), (1, 1)]), includeOnHull: false).coords == correct)
        #expect(trivialHull(coords([(0, 0), (1, 1)]), includeOnHull: true).coords == correct)
    }

    @Test func twoPointsDuplicated() {
        let correct = coords([(0, 0), (0, 0)])
        #expect(trivialHull(coords([(0, 0), (0, 0)]), includeOnHull: false).coords == correct)
        #expect(trivialHull(coords([(0, 0), (0, 0)]), includeOnHull: true).coords == correct)
    }

    @Test func threePointsCCW() {
        #expect(trivialHull(coords([(0, 0), (1, 0), (1, 1)]), includeOnHull: false).coords
            == coords([(0, 0), (1, 0), (1, 1), (0, 0)]))
    }

    @Test func threePointsCW() {
        #expect(trivialHull(coords([(0, 0), (1, 1), (1, 0)]), includeOnHull: false).coords
            == coords([(0, 0), (1, 0), (1, 1), (0, 0)]))
    }

    @Test func threePointsTwoDuplicated() {
        #expect(trivialHull(coords([(0, 0), (1, 1), (0, 0)]), includeOnHull: false).coords
            == coords([(0, 0), (1, 1), (0, 0)]))
        #expect(trivialHull(coords([(0, 0), (1, 1), (0, 0)]), includeOnHull: true).coords
            == coords([(0, 0), (1, 1), (0, 0)]))
    }

    @Test func threePointsDuplicated() {
        #expect(trivialHull(coords([(0, 0), (0, 0), (0, 0)]), includeOnHull: false).coords
            == coords([(0, 0), (0, 0)]))
        #expect(trivialHull(coords([(0, 0), (0, 0), (0, 0)]), includeOnHull: true).coords
            == coords([(0, 0), (0, 0), (0, 0)]))
    }

    @Test func threeCollinearPoints() {
        #expect(trivialHull(coords([(0, 0), (1, 1), (2, 2)]), includeOnHull: false).coords
            == coords([(0, 0), (2, 2), (0, 0)]))
        #expect(trivialHull(coords([(0, 0), (1, 1), (2, 2)]), includeOnHull: true).coords
            == coords([(0, 0), (1, 1), (2, 2), (0, 0)]))
    }
}

@Suite struct ConvexHullTests {
    private let star: [(Double, Double)] = [
        (0, 10), (1, 1), (10, 0), (1, -1), (0, -10), (-1, -1), (-10, 0), (-1, 1), (0, 10),
    ]
    private let starHull: [(Double, Double)] = [(0, -10), (10, 0), (0, 10), (-10, 0), (0, -10)]

    @Test func multipoint() {
        let mp = GeoMultiPoint(star.map { geoP($0.0, $0.1) })
        #expect(mp.convexHull().exterior.coords == coords(starHull))
    }

    @Test func linestring() {
        #expect(geoLS(star).convexHull().exterior.coords == coords(starHull))
    }

    @Test func multilinestring() {
        let mls = GeoMultiLineString([geoLS([(0, 0), (1, 10)]), geoLS([(1, 10), (2, 0), (3, 1)])])
        #expect(mls.convexHull().exterior.coords == coords([(2, 0), (3, 1), (1, 10), (0, 0), (2, 0)]))
    }

    @Test func multipolygon() {
        let mp = GeoMultiPolygon([
            geoPoly([(0, 0), (1, 10), (2, 0), (0, 0)]),
            geoPoly([(3, 0), (4, 10), (5, 0), (3, 0)]),
        ])
        #expect(mp.convexHull().exterior.coords == coords([(5, 0), (4, 10), (1, 10), (0, 0), (5, 0)]))
    }

    @Test func quickHull1() {
        var v = coords([(0, 0), (4, 0), (4, 1), (1, 1), (1, 4), (0, 4), (0, 0)])
        #expect(quickHull(&v).isStrictlyCCWConvex)
    }

    @Test func quickHull2() {
        var v = coords(star)
        #expect(quickHull(&v).coords == coords(starHull))
    }

    @Test func quickHullCCW() {
        var v = coords([(1, 0), (2, 1), (1.75, 1.1), (1, 2), (0, 1), (1, 0)])
        #expect(quickHull(&v).coords == coords([(1, 0), (2, 1), (1, 2), (0, 1), (1, 0)]))
    }

    @Test func quickHullCCWMaintain() {
        var v = coords([(0, 0), (2, 0), (2.5, 1.75), (2.3, 1.7), (1.75, 2.5), (1.3, 2), (0, 2), (0, 0)])
        #expect(quickHull(&v).isStrictlyCCWConvex)
    }

    @Test func quickHullCollinear() {
        // Three points share the least x: the middle one is not on the output.
        var v = coords([(-1, 0), (-1, -1), (-1, 1), (0, 0), (0, -1), (0, 1), (1, 0), (1, -1), (1, 1)])
        #expect(quickHull(&v).isStrictlyCCWConvex)
    }

    @Test(.disabled("reads geo-test-fixtures (poly1, poly1_hull), which is not in the cargo registry"))
    func quickHullComplex() {}

    @Test(.disabled("reads geo-test-fixtures (poly2, poly2_hull), which is not in the cargo registry"))
    func quickHullComplex2() {}
}

@Suite struct IsConvexTests {
    @Test func cornerCases() {
        let empty = GeoLineString([])
        #expect(empty.isCollinear)
        #expect(!empty.isConvex)
        #expect(!empty.isStrictlyCCWConvex)

        let one = geoLS([(0, 0)])
        #expect(one.isCollinear)
        #expect(one.isConvex)
        #expect(one.isCWConvex)
        #expect(one.isCCWConvex)
        #expect(one.isStrictlyConvex)
        #expect(!one.isStrictlyCCWConvex)
        #expect(!one.isStrictlyCWConvex)

        let oneRep = geoLS([(0, 0), (0, 0)])
        #expect(oneRep.isCollinear)
        #expect(oneRep.isConvex)
        #expect(oneRep.isCWConvex)
        #expect(oneRep.isCCWConvex)
        #expect(!oneRep.isStrictlyConvex)
        #expect(!oneRep.isStrictlyCCWConvex)
        #expect(!oneRep.isStrictlyCWConvex)

        var two = geoLS([(0, 0), (1, 1)])
        #expect(two.isCollinear)
        #expect(!two.isConvex)

        two.close()
        #expect(two.isCWConvex)
        #expect(two.isCCWConvex)
        #expect(!two.isStrictlyConvex)
        #expect(!two.isStrictlyCCWConvex)
        #expect(!two.isStrictlyCWConvex)
    }
}
