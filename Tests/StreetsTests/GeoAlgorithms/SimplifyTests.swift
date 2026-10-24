/// The tests of geo 0.27's `simplify.rs` (Ramer-Douglas-Peucker) and `simplify_vw.rs`
/// (Visvalingam-Whyatt, plain and preserving). The tests over geo-test-fixtures are skipped: the
/// crate is not in the cargo registry.

@testable import GeoAlgorithms
import Testing

@Suite struct SimplifyTests {
    @Test func recursion() {
        let input = [geoC(8, 100), geoC(9, 100), geoC(12, 100)]
        #expect(rdp(input, 1.0, initialMin: 2) == [geoC(8, 100), geoC(12, 100)])
    }

    @Test func rdpBasic() {
        let vec = [geoC(0, 0), geoC(5, 4), geoC(11, 5.5), geoC(17.3, 3.2), geoC(27.8, 0.1)]
        let compare = [geoC(0, 0), geoC(5, 4), geoC(11, 5.5), geoC(27.8, 0.1)]
        #expect(rdp(vec, 1.0, initialMin: 2) == compare)
    }

    @Test func rdpEmptyLinestring() {
        #expect(rdp([], 1.0, initialMin: 2) == [])
    }

    @Test func rdpTwoPointLinestring() {
        let vec = [geoC(0, 0), geoC(27.8, 0.1)]
        #expect(rdp(vec, 1.0, initialMin: 2) == vec)
    }

    @Test func multilinestring() {
        let mline = GeoMultiLineString([geoLS([(0, 0), (5, 4), (11, 5.5), (17.3, 3.2), (27.8, 0.1)])])
        #expect(mline.simplify(1.0) == GeoMultiLineString([geoLS([(0, 0), (5, 4), (11, 5.5), (27.8, 0.1)])]))
    }

    @Test func polygon() {
        let polygon = geoPoly([(0, 0), (0, 10), (5, 11), (10, 10), (10, 0), (0, 0)])
        #expect(polygon.simplify(2) == geoPoly([(0, 0), (0, 10), (10, 10), (10, 0), (0, 0)]))
    }

    @Test func multipolygon() {
        let mpoly = GeoMultiPolygon([geoPoly([(0, 0), (0, 10), (5, 11), (10, 10), (10, 0), (0, 0)])])
        #expect(mpoly.simplify(2) == GeoMultiPolygon([geoPoly([(0, 0), (0, 10), (10, 10), (10, 0), (0, 0)])]))
    }

    @Test func simplifyNegativeEpsilon() {
        let lineString = geoLS([(0, 0), (0, 10), (5, 11), (10, 10), (10, 0)])
        #expect(lineString.simplify(-1.0) == lineString)
    }

    @Test func simplifyIdxNegativeEpsilon() {
        let lineString = geoLS([(0, 0), (0, 10), (5, 11), (10, 10), (10, 0)])
        #expect(lineString.simplifyIdx(-1.0) == [0, 1, 2, 3, 4])
    }

    @Test func simplifyLineStringPolygonInitialMin() {
        let lineString = geoLS([
            (1.4324054e-16, 1.4324054e-16),
            (1.4324054e-16, 1.4324054e-16),
            (-5.9730447e26, 1.5590374e-27),
            (1.4324054e-16, 1.4324054e-16),
        ])
        let epsilon = 3.46e-43
        // The line string keeps three coordinates.
        #expect(lineString.simplify(epsilon) == geoLS([
            (1.4324054e-16, 1.4324054e-16),
            (-5.9730447e26, 1.5590374e-27),
            (1.4324054e-16, 1.4324054e-16),
        ]))
        // The polygon keeps all four.
        #expect(GeoPolygon(lineString, []).simplify(epsilon) == geoPoly([
            (1.4324054e-16, 1.4324054e-16),
            (1.4324054e-16, 1.4324054e-16),
            (-5.9730447e26, 1.5590374e-27),
            (1.4324054e-16, 1.4324054e-16),
        ]))
    }

    @Test func dontOversimplify() {
        let unsimplified = geoLS([(0, 0), (5, 4), (11, 5.5), (17.3, 3.2), (27.8, 0.1)])
        #expect(unsimplified.simplify(30) == geoLS([(0, 0), (27.8, 0.1)]))
    }
}

@Suite struct SimplifyVwTests {
    /// geo issue 1049, a `#[should_panic]` test: the simplification does not give the expected
    /// polygon, so the `assert_eq!` panics. Here the simplification runs, then the result must
    /// differ from that polygon.
    @Test func vwpBug() {
        let polygon = geoPoly([(1, 4), (3, 4), (1, 1), (7, 0), (1, 0), (0, 1), (1, 4)])
        let simplified = polygon.simplifyVwPreserve(2.25)
        #expect(simplified != geoPoly([(1, 4), (3, 4), (1, 1), (7, 0), (1, 0), (1, 4)]))
    }

    @Test func visvalingamPostGIS() {
        let lineString = geoLS([(5, 2), (3, 8), (6, 20), (7, 25), (10, 10)])
        #expect(visvalingam(lineString, 30) == [geoC(5, 2), geoC(7, 25), geoC(10, 10)])
    }

    @Test func simpleVwp() {
        // Removing the point of the smallest triangle (1, 2, 3), area 668.5, would make (0, 1, 3)
        // cross (3, 4, 5), so point 1 goes too, leaving (0, 3, 4, 5, 6, 7).
        let lineString = geoLS([(10, 60), (135, 68), (94, 48), (126, 31), (280, 19), (117, 48), (300, 40), (301, 10)])
        let simplified = vwpWrapper(lineString, nil, 668.6, initialMin: 2, minPoints: 4)
        #expect(simplified[0] == [geoC(10, 60), geoC(126, 31), geoC(280, 19), geoC(117, 48), geoC(300, 40), geoC(301, 10)])
    }

    @Test func simplifyVwPreserveDocExample() {
        let lineString = geoLS([(10, 60), (135, 68), (94, 48), (126, 31), (280, 19), (117, 48), (300, 40), (301, 10)])
        let expected = geoLS([(10, 60), (126, 31), (280, 19), (117, 48), (300, 40), (301, 10)])
        #expect(approxRelativeEq(lineString.simplifyVwPreserve(668.6), expected, epsilon: 1e-6))
    }

    private let outer: [(Double, Double)] = [
        (-54.4921875, 21.289374355860424),
        (-33.5, 56.9449741808516),
        (-22.5, 44.08758502824516),
        (-19.5, 23.241346102386135),
        (-54.4921875, 21.289374355860424),
    ]

    @Test func retainedVwp() {
        // Removing outer[2] would cross the inner ring and force outer[1] out too, leaving too
        // few points, so it stays. The inner ring is at the polygon minimum already.
        let inner = geoLS([
            (-24.451171875, 35.266685523707665),
            (-29.513671875, 47.32027765985069),
            (-22.869140625, 43.80817468459856),
            (-24.451171875, 35.266685523707665),
        ])
        let polygon = GeoPolygon(geoLS(outer), [inner])
        let simplified = polygon.simplifyVwPreserve(95.4)
        #expect(approxRelativeEq(simplified.exterior, geoLS(outer), epsilon: 1e-6))
    }

    @Test func removeInnerPointVwp() {
        // As above for the exterior, and the inner ring loses inner[2].
        let inner = geoLS([
            (-24.451171875, 35.266685523707665),
            (-40.0, 45.0),
            (-29.513671875, 47.32027765985069),
            (-22.869140625, 43.80817468459856),
            (-24.451171875, 35.266685523707665),
        ])
        let correctInner = geoLS([
            (-24.451171875, 35.266685523707665),
            (-40.0, 45.0),
            (-22.869140625, 43.80817468459856),
            (-24.451171875, 35.266685523707665),
        ])
        let polygon = GeoPolygon(geoLS(outer), [inner])
        let simplified = polygon.simplifyVwPreserve(95.4)
        #expect(simplified.exterior == geoLS(outer))
        #expect(simplified.interiors[0] == correctInner)
    }

    @Test(.disabled("reads geo-test-fixtures (norway_main), which is not in the cargo registry"))
    func veryLongVwp() {}

    @Test(.disabled("reads geo-test-fixtures (vw_orig, vw_simplified), which is not in the cargo registry"))
    func visvalingamLong() {}

    @Test(.disabled("reads geo-test-fixtures (vw_orig, vw_simplified), which is not in the cargo registry"))
    func visvalingamPreserveLong() {}

    @Test func visvalingamEmptyLinestring() {
        #expect(visvalingam(GeoLineString([]), 1.0) == [])
    }

    @Test func visvalingamTwoPointLinestring() {
        #expect(visvalingam(geoLS([(0, 0), (27.8, 0.1)]), 1.0) == [geoC(0, 0), geoC(27.8, 0.1)])
    }

    @Test func multilinestring() {
        let mline = GeoMultiLineString([geoLS([(5, 2), (3, 8), (6, 20), (7, 25), (10, 10)])])
        let simplified = mline.simplifyVw(30)
        #expect(simplified.lineStrings.count == 1)
        #expect(approxRelativeEq(simplified.lineStrings[0], geoLS([(5, 2), (7, 25), (10, 10)]), epsilon: 1e-6))
    }

    @Test func polygon() {
        let polygon = geoPoly([(0, 0), (0, 10), (5, 11), (10, 10), (10, 0), (0, 0)])
        #expect(approxRelativeEq(polygon.simplifyVw(10), geoPoly([(0, 0), (0, 10), (10, 10), (10, 0), (0, 0)]), epsilon: 1e-6))
    }

    @Test func multipolygon() {
        let mpoly = GeoMultiPolygon([geoPoly([(0, 0), (0, 10), (5, 11), (10, 10), (10, 0), (0, 0)])])
        let simplified = mpoly.simplifyVw(10)
        #expect(simplified.polygons.count == 1)
        #expect(approxRelativeEq(simplified.polygons[0], geoPoly([(0, 0), (0, 10), (10, 10), (10, 0), (0, 0)]), epsilon: 1e-6))
    }
}
