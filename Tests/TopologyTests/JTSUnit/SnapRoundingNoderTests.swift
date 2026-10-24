import Foundation
import Testing
import Topology

/// JTS's unit tests of snap rounding (`SnapRoundingNoderTest` of JTS 1.20),
/// as JTS runs them: the lines noded, the result checked to be fully noded
/// (`ValidatingNoder`), and, where JTS gives one, compared with the expected
/// lines, both normalized. GEOS does not expose the snap-rounding noder alone:
/// it is compared with GEOS through the overlays at a precision (phase 4,
/// `OverlayParityTests.fixedPrecisionOverlay`).
@Suite struct SnapRoundingNoderTests {
    static let cases: [(String, String, Double, String?)] = [
        ("testSimple", "MULTILINESTRING ((1 1, 9 2), (3 3, 3 0))", 1, "MULTILINESTRING ((1 1, 3 1), (3 1, 9 2), (3 3, 3 1), (3 1, 3 0))"),
        ("testSnappedDiagonalLine", "LINESTRING (2 3, 3 3, 3 2, 2 3)", 1.0, "MULTILINESTRING ((2 3, 3 3), (2 3, 3 3), (3 2, 3 3), (3 2, 3 3))"),
        ("testRingsWithParallelNarrowSpikes", "MULTILINESTRING ((1 3.3, 1.3 1.4, 3.1 1.4, 3.1 0.9, 1.3 0.9, 1 -0.2, 0.8 1.3, 1 3.3), (1 2.9, 2.9 2.9, 2.9 1.3, 1.7 1, 1.3 0.9, 1 0.4, 1 2.9))", 1.0, "MULTILINESTRING ((1 3, 1 1), (1 1, 2 1), (2 1, 3 1), (3 1, 2 1), (2 1, 1 1), (1 1, 1 0), (1 0, 1 1), (1 1, 1 3), (1 3, 3 3, 3 1), (3 1, 2 1), (2 1, 1 1), (1 1, 1 0), (1 0, 1 1), (1 1, 1 3))"),
        ("testHorizontalLinesWithMiddleNode", "MULTILINESTRING ((2.5117493 49.0278625,                      2.5144958 49.0278625), (2.511749 49.027863, 2.513123 49.027863, 2.514496 49.027863))", 1000000.0, "MULTILINESTRING ((2.511749 49.027863, 2.513123 49.027863), (2.511749 49.027863, 2.513123 49.027863), (2.513123 49.027863, 2.514496 49.027863), (2.513123 49.027863, 2.514496 49.027863))"),
        ("testSlantAndHorizontalLineWithMiddleNode", "MULTILINESTRING ((0.1565552 49.5277405, 0.1579285 49.5277405, 0.1593018 49.5277405), (0.1568985 49.5280838, 0.1589584 49.5273972))", 1000000.0, "MULTILINESTRING ((0.156555 49.527741, 0.157928 49.527741), (0.156899 49.528084, 0.157928 49.527741), (0.157928 49.527741, 0.157929 49.527741, 0.159302 49.527741), (0.157928 49.527741, 0.158958 49.527397))"),
        ("testNearbyCorner", "MULTILINESTRING ((0.2 1.1, 1.6 1.4, 1.9 2.9), (0.9 0.9, 2.3 1.7))", 1.0, "MULTILINESTRING ((0 1, 1 1), (1 1, 2 1), (1 1, 2 1), (2 1, 2 2), (2 1, 2 2), (2 2, 2 3))"),
        ("testNearbyShape", "MULTILINESTRING ((1.3 0.1, 2.4 3.9), (0 1, 1.53 1.48, 0 4))", 1.0, "MULTILINESTRING ((1 0, 2 1), (2 1, 2 4), (0 1, 2 1), (2 1, 0 4))"),
        ("testIntOnGridCorner", "MULTILINESTRING ((4.30166242 45.53438188, 4.30166243 45.53438187), (4.3011475 45.5328371, 4.3018341 45.5348969))", 100000000, nil),
        ("testVertexCrossesLine", "MULTILINESTRING ((2.2164917 48.8864136, 2.2175217 48.8867569), (2.2175217 48.8867569, 2.2182083 48.8874435), (2.2182083 48.8874435, 2.2161484 48.8853836))", 1000000, nil),
        ("testVertexCrossesLine2", "MULTILINESTRING ((2.276916574988164 49.06082147500638, 2.2769165 49.0608215), (2.2769165 49.0608215, 2.2755432 49.0608215), (2.2762299 49.0615082, 2.276916574988164 49.06082147500638))", 1000000, nil),
        ("testShortLineNodeNotAdded", "LINESTRING (2.1279144 48.8445282, 2.126884443750796 48.84555818124935, 2.1268845 48.8455582, 2.1268845 48.8462448)", 1000000, "MULTILINESTRING ((2.127914 48.844528, 2.126885 48.845558), (2.126885 48.845558, 2.126884 48.845558), (2.126884 48.845558, 2.126885 48.845558), (2.126885 48.845558, 2.126885 48.846245))"),
        ("testDiagonalNotNodedRightUp", "MULTILINESTRING ((0 0, 10 10), ( 0 2, 4.55 5.4, 9 10 ))", 1, nil),
        ("testDiagonalNotNodedLeftUp", "MULTILINESTRING ((10 0, 0 10), ( 10 2, 5.45 5.45, 1 10 ))", 1, nil),
        ("testDiagonalNotNodedOriginal", "MULTILINESTRING (( 2.45167 48.96709, 2.45768 48.9731 ), (2.4526978 48.968811, 2.4537277 48.9691544, 2.4578476 48.9732742))", 100000, nil),
        ("testLoopBackCreatesNode", "LINESTRING (2 2, 5 2, 8 4, 5 6, 4.8 2.3, 2 5)", 1, "MULTILINESTRING ((2 2, 5 2), (5 2, 8 4, 5 6, 5 2), (5 2, 2 5))"),
        ("testNearVertexNotNoded", "MULTILINESTRING ((2.4829102 48.8726807, 2.4830818249999997 48.873195575, 2.4839401 48.8723373), ( 2.4829102 48.8726807, 2.4832535 48.8737106 ))", 100000000, nil),
        ("testVertexNearHorizSegNotNoded", "MULTILINESTRING (( 2.5096893 48.9530182, 2.50762932500455 48.95233152500091, 2.5055695 48.9530182 ), ( 2.5090027 48.9523315, 2.5035095 48.9523315 ))", 1000000, nil),
        ("testMCIndexNoderTolerance", "LINESTRING (3670939.6336634574 3396937.3777869204, 3670995.4715200397 3396926.0316904164, 3671077.280213823 3396905.4302639295, 3671203.8838707027 3396908.120176068, 3671334.962571111 3396904.8310892633, 3670037.299066126 3396904.8310892633, 3670037.299066126 3398075.9808747065, 3670939.6336634574 3396937.3777869204)", 0.0016339869, "MULTILINESTRING ((3670776.0631373483 3397212.0584320477, 3670776.0631373483 3396600.058421521), (3670776.0631373483 3396600.058421521, 3671388.063147875 3396600.058421521), (3671388.063147875 3396600.058421521, 3671388.063147875 3397212.0584320477), (3671388.063147875 3397212.0584320477, 3671388.063147875 3396600.058421521), (3671388.063147875 3396600.058421521, 3671388.063147875 3397212.0584320477), (3671388.063147875 3397212.0584320477, 3671388.063147875 3396600.058421521), (3671388.063147875 3396600.058421521, 3670776.0631373483 3396600.058421521), (3670776.0631373483 3396600.058421521, 3670164.063126822 3396600.058421521, 3670164.063126822 3397824.058442574, 3670776.0631373483 3397212.0584320477))"),
    ]

    @Test(arguments: SnapRoundingNoderTests.cases.map(\.0))
    func jtsCase(_ name: String) throws {
        let (_, wkt, scale, expected) = SnapRoundingNoderTests.cases.first { $0.0 == name }!
        let geom = try WKTReader().read(wkt)
        var lines: [LineString] = []
        geom.applyComponents { if let l = $0 as? LineString { lines.append(l) } }
        let strings: [SegmentString] = lines.map { NodedSegmentString($0.getCoordinates(), $0) }
        let noder = SnapRoundingNoder(PrecisionModel(scale: scale))
        try ValidatingNoder(noder).computeNodes(strings)
        let noded = noder.getNodedSubstrings().map { geom.factory.createLineString($0.getCoordinates()) }
        let result: Geometry = noded.count == 1 ? noded[0] : geom.factory.createMultiLineString(noded)
        guard let expected else { return }
        // JTS's expected points are on JTS's grid (`k / scale`). The port rounds
        // as GEOS 3.13 does (on the grid size `1 / scale` when it is above 1):
        // the expected points made precise by the model are on its grid.
        let pm = PrecisionModel(scale: scale)
        let e = try WKTReader(GeometryFactory(precisionModel: pm)).read(expected)
        #expect(result.norm().equalsExact(e.norm()), "\(name): \(result)")
    }
}
