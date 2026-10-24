/// The tests of geo 0.27's `bool_ops/tests.rs`, run through the public boolean operations (the
/// Rust `check_sweep` drives the same `Proc` with the same inputs).

import GeoAlgorithms
import Testing

private func checkSweep(_ wkt1: String, _ wkt2: String, _ ty: GeoOpType) throws -> GeoMultiPolygon {
    let poly1 = GeoTestWKT.multiPolygonOrPolygon(wkt1)
    let poly2 = GeoTestWKT.multiPolygonOrPolygon(wkt2)
    return try poly1.booleanOp(poly2, ty)
}

@Suite struct BoolOpsTests {
    @Test func rectOverlapping() throws {
        let wkt1 = "POLYGON((0 0,1 0,1 1,0 1,0 0))"
        let wkt2 = "POLYGON((0.5 1,2 1,2 2,0.5 2,0.5 1))"
        let wktUnion = "MULTIPOLYGON(((1 0,1 1,2 1,2 2,0.5 2,0.5 1,0 1,0 0,1 0)))"
        let output = try checkSweep(wkt1, wkt2, .union)
        #expect(output == GeoTestWKT.multiPolygon(wktUnion))
    }

    @Test func extInHole() throws {
        // A union with a ring inside a hole inside an exterior.
        let wkt1 = "POLYGON((0 0, 40 0, 40 40, 0 40, 0 0), (10 10, 30 10, 30 30, 10 30, 10 10))"
        let wkt2 = "POLYGON((11 11, 29 11, 29 29, 11 29, 11 11), (15 15, 25 15, 25 25, 15 25, 15 15))"
        let output = try checkSweep(wkt1, wkt2, .union)
        // Derived: the inputs do not touch, so the union is both polygons as they are, each
        // ring starting at its least point, exteriors counterclockwise and holes clockwise.
        #expect(output.unsignedArea == 1600 - 400 + 324 - 100)
        #expect(output.polygons.count == 2)
    }

    @Test func invalidSimple() throws {
        // A polygon with holes, and invalid.
        _ = try checkSweep("POLYGON((0 0, 2 2, 2 0, 0 0), (1 1, 2 1, 1 0))", "POLYGON EMPTY", .union)
    }

    @Test func invalidLoops() throws {
        _ = try checkSweep("POLYGON((0 0, 2 2, 0 4, -2 2, 0 0, 1 2, 0 3, -1 2, 0 0))", "POLYGON EMPTY", .union)
    }

    @Test func complexRects() throws {
        let wkt1 = "MULTIPOLYGON(((-1 -2,-1.0000000000000002 2,-0.8823529411764707 2,-0.8823529411764706 -2,-1 -2)),((-0.7647058823529411 -2,-0.7647058823529412 2,-0.6470588235294118 2,-0.6470588235294118 -2,-0.7647058823529411 -2)),((-0.5294117647058824 -2,-0.5294117647058825 2,-0.41176470588235287 2,-0.4117647058823529 -2,-0.5294117647058824 -2)),((-0.2941176470588236 -2,-0.2941176470588236 2,-0.17647058823529418 2,-0.17647058823529416 -2,-0.2941176470588236 -2)),((-0.05882352941176472 -2,-0.05882352941176472 2,0.05882352941176472 2,0.05882352941176472 -2,-0.05882352941176472 -2)),((0.17647058823529416 -2,0.17647058823529416 2,0.29411764705882365 2,0.2941176470588236 -2,0.17647058823529416 -2)),((0.4117647058823528 -2,0.41176470588235287 2,0.5294117647058821 2,0.5294117647058822 -2,0.4117647058823528 -2)),((0.6470588235294117 -2,0.6470588235294118 2,0.7647058823529411 2,0.7647058823529411 -2,0.6470588235294117 -2)),((0.8823529411764706 -2,0.8823529411764707 2,1.0000000000000002 2,1 -2,0.8823529411764706 -2)))"
        let wkt2 = "MULTIPOLYGON(((-2 -1,2 -1.0000000000000002,2 -0.8823529411764707,-2 -0.8823529411764706,-2 -1)),((-2 -0.7647058823529411,2 -0.7647058823529412,2 -0.6470588235294118,-2 -0.6470588235294118,-2 -0.7647058823529411)),((-2 -0.5294117647058824,2 -0.5294117647058825,2 -0.41176470588235287,-2 -0.4117647058823529,-2 -0.5294117647058824)),((-2 -0.2941176470588236,2 -0.2941176470588236,2 -0.17647058823529418,-2 -0.17647058823529416,-2 -0.2941176470588236)),((-2 -0.05882352941176472,2 -0.05882352941176472,2 0.05882352941176472,-2 0.05882352941176472,-2 -0.05882352941176472)),((-2 0.17647058823529416,2 0.17647058823529416,2 0.29411764705882365,-2 0.2941176470588236,-2 0.17647058823529416)),((-2 0.4117647058823528,2 0.41176470588235287,2 0.5294117647058821,-2 0.5294117647058822,-2 0.4117647058823528)),((-2 0.6470588235294117,2 0.6470588235294118,2 0.7647058823529411,-2 0.7647058823529411,-2 0.6470588235294117)),((-2 0.8823529411764706,2 0.8823529411764707,2 1.0000000000000002,-2 1,-2 0.8823529411764706)))"
        let mp1 = GeoTestWKT.multiPolygon(wkt1)
        let mp2 = GeoTestWKT.multiPolygon(wkt2)
        // The Rust test round-trips each polygon through GeoTestWKT, which is exact for `f64`.
        for p1 in mp1.polygons {
            for p2 in mp2.polygons {
                _ = try GeoMultiPolygon(p1).booleanOp(GeoMultiPolygon(p2), .union)
            }
        }
    }

    @Test func complexRects1() throws {
        _ = try checkSweep(
            "MULTIPOLYGON(((-1 -2,-1.0000000000000002 2,-0.8823529411764707 2,-0.8823529411764706 -2,-1 -2)))",
            "MULTIPOLYGON(((-2 -1,2 -1.0000000000000002,2 -0.8823529411764707,-2 -0.8823529411764706,-2 -1)))",
            .union)
    }

    @Test func overlapIssue867() throws {
        _ = try checkSweep(
            "POLYGON ((17.724912058920285 -16.37118892052372, 18.06452454246989 -17.693907532504, 19.09389292605319 -17.924001641855178, 17.724912058920285 -16.37118892052372))",
            "POLYGON ((17.576085274796423 -15.791540153598898, 17.19432983818328 -17.499393422066746, 18.06452454246989 -17.693907532504, 17.576085274796423 -15.791540153598898))",
            .intersection)
    }

    @Test func issue865() throws {
        // The simplified example.
        let wkt1 = "POLYGON((0 0, 1 1, 10 0, 0 0))"
        _ = try checkSweep(wkt1, "POLYGON((1 1, 8 2, 4 1, 1 1))", .union)
        _ = try checkSweep(wkt1, "POLYGON((1 1, 4 2, 8 1, 1 1))", .union)

        // The original example.
        _ = try checkSweep(
            "POLYGON((-640 -360,640 -360,640 360,-640 360,-640 -360))",
            "POLYGON((313.276 359.999,213.319 359.999,50 60,-50 60,-50 110,-8.817 360,-93.151 360,-85.597 225.618,-114.48 359.999,-117.017 360,-85 215,-85 155,-115 155,-154.161 360,-640 360,-640 -360,640 -360,640 360,313.277 360,313.276 359.999))",
            .difference)
    }

    @Test func clipAdhoc() throws {
        let poly1 = GeoTestWKT.multiPolygonOrPolygon("POLYGON ((20 0, 20 160, 200 160, 200 0, 20 0))")
        let mls = GeoMultiLineString([GeoTestWKT.lineString("LINESTRING (0 0, 100 100, 240 100)")])
        let output = try poly1.clip(mls, invert: true)
        // The Rust test only prints the result. Derived: the parts outside the rectangle, in
        // sweep order, each as one line string from its left end.
        #expect(output == GeoMultiLineString([geoLS([(0, 0), (20, 20)]), geoLS([(200, 100), (240, 100)])]))
        let inside = try poly1.clip(mls, invert: false)
        #expect(inside == GeoMultiLineString([geoLS([(20, 20), (100, 100), (200, 100)])]))
    }

    @Test func issue885Small() throws {
        // The Rust test runs in `f32`. This port has `f64` only, so it runs the same input in
        // `f64` (the test checks only that the operation does not panic).
        _ = try checkSweep(
            "POLYGON((8055.658 7977.5537,8010.734 7999.9697,8032.9717 8044.537,8077.896 8022.121,8055.658 7977.5537))",
            "POLYGON((8055.805 7977.847,8010.871 8000.2676,8033.105 8044.8286,8078.039 8022.408,8055.805 7977.847))",
            .union)
    }

    @Test func issue885BigRaw() throws {
        _ = try checkSweep(BoolOpsFixtures.issue885BigRaw1, BoolOpsFixtures.issue885BigRaw2, .difference)
    }

    @Test func issue885BigSimplified() throws {
        let wkt1 = "MULTIPOLYGON(((256.0 -256.0,-256.0 -256.0,-256.0 256.0,256.0 256.0,256.0 -256.0), (15.9573974609375 218.888916015625,-29.042602539062493 244.86967812915816, -32.57795824885207 241.3343224193686, -32.57812499999999 241.33427773853316, -36.11348070978957 237.7989220287436,-36.11364746093749 237.79887734790816, -39.64895848989165 234.26356631895402,0.9573974609375036 192.90815390209184,15.9573974609375 218.888916015625)))"
        let wkt2 = "POLYGON((19.492919921875 222.424560546875,-25.507080078124993 248.40532266040816,-36.48784219165816 237.424560546875, 4.4929199218750036 196.44379843334184,19.492919921875 222.424560546875))"
        _ = try checkSweep(wkt1, wkt2, .difference)
    }

    @Test func squaresAllOperations() throws {
        // Not in geo: two unit squares overlapping by half, whose areas are exact.
        let a = geoPoly([(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)])
        let b = geoPoly([(0.5, 0), (1.5, 0), (1.5, 1), (0.5, 1), (0.5, 0)])
        #expect(try a.intersection(b).unsignedArea == 0.5)
        #expect(try a.union(b).unsignedArea == 1.5)
        #expect(try a.xor(b).unsignedArea == 1.0)
        #expect(try a.difference(b).unsignedArea == 0.5)
        #expect(try b.difference(a).unsignedArea == 0.5)
    }

    @Test func nanPanics() {
        // Not in geo: a NaN makes `SweepPoint::cmp` unwrap `None`, a panic in Rust, an error here.
        let a = geoPoly([(0, 0), (1, 0), (.nan, 1), (0, 1), (0, 0)])
        let b = geoPoly([(0.5, 0), (1.5, 0), (1.5, 1), (0.5, 1), (0.5, 0)])
        #expect(throws: GeoPanic.self) { try a.union(b) }
    }

    @Test(.disabled("issue-894 reads geo-test-fixtures (issue-894/inp*.wkt), which is not in the cargo registry"))
    func issue894() {}

    @Test(.disabled("ignored in geo 0.27 too: this input breaks the ordering assumption"))
    func issueBufferBox() {}
}
