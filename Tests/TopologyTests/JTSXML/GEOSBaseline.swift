/// What GEOS 3.13 did on the JTS 1.20.0 XML suites, as its run of the runner
/// found it before phase 12 (written by that test, removed with GEOS): the count per
/// suite and every test GEOS does not pass, with why.
enum GEOSBaseline {
    static let summary = [
        "general: 2411 passed, 65 failed, 1 errors, 0 unsupported",
        "validate: 5325 passed, 1 failed, 0 errors, 0 unsupported",
        "robust: 2089 passed, 2 failed, 0 errors, 0 unsupported",
        "misc: 498 passed, 5 failed, 1 errors, 0 unsupported",
    ]

    static let notPassed = [
        "general/TestBufferMitredJoin.xml#1.1", // failed: POLYGON ((588734.1297709366 4518928.603482892, 588720.8876067492 4518935.1084635
        "general/TestBufferMitredJoin.xml#2.1", // failed: POLYGON ((589293.0184401305 4519625.542333956, 589292.3401596148 4519624.4196591
        "general/TestBufferMitredJoin.xml#4.1", // failed: POLYGON ((589095.5323892826 4518493.322025424, 589092.8222002359 4518488.7639438
        "general/TestCentroid.xml#10.1", // error: input: unreadable: ParseException: Unexpected text after end of geometry
        "general/TestCentroid.xml#37.1", // failed: POINT (56.52883333333333 25.210333333333335)
        "general/TestDensify.xml#13.1", // failed: POLYGON ((0 0, 0 10, 0 20, 0 30, 0 40, 0 50, 0 60, 0 70, 10 70, 20 70, 30 70, 40
        "general/TestDensify.xml#14.1", // failed: MULTIPOLYGON (((0 0, 0 10, 0 20, 0 30, 0 40, 0 50, 0 60, 0 70, 10 70, 20 70, 30 
        "general/TestInteriorPoint.xml#22.1", // failed: POINT EMPTY
        "general/TestInteriorPoint.xml#23.1", // failed: POINT EMPTY
        "general/TestMinimumClearance.xml#1.1", // failed: inf
        "general/TestMinimumClearance.xml#2.1", // failed: inf
        "general/TestMinimumClearance.xml#4.1", // failed: inf
        "general/TestMinimumClearance.xml#7.1", // failed: inf
        "general/TestMinimumClearance.xml#9.1", // failed: inf
        "general/TestNGOverlayA.xml#18.2", // failed: MULTIPOLYGON (((10 10, 10 30, 30 30, 30 10, 10 10)), EMPTY)
        "general/TestNGOverlayA.xml#18.5", // failed: MULTIPOLYGON (((10 10, 10 30, 30 30, 30 10, 10 10)), EMPTY)
        "general/TestNGOverlayEmpty.xml#1.2", // failed: MULTIPOLYGON (((10 10, 10 30, 30 30, 30 10, 10 10)), EMPTY)
        "general/TestNGOverlayEmpty.xml#1.5", // failed: MULTIPOLYGON (((10 10, 10 30, 30 30, 30 10, 10 10)), EMPTY)
        "general/TestNGOverlayEmpty.xml#10.2", // failed: GEOMETRYCOLLECTION (POINT (10 10), LINESTRING EMPTY)
        "general/TestNGOverlayEmpty.xml#10.5", // failed: GEOMETRYCOLLECTION (POINT (10 10), LINESTRING EMPTY)
        "general/TestNGOverlayEmpty.xml#11.2", // failed: MULTIPOINT ((10 10), EMPTY)
        "general/TestNGOverlayEmpty.xml#11.5", // failed: MULTIPOINT ((10 10), EMPTY)
        "general/TestNGOverlayEmpty.xml#12.2", // failed: MULTIPOINT (EMPTY, EMPTY)
        "general/TestNGOverlayEmpty.xml#2.2", // failed: MULTIPOLYGON (EMPTY, EMPTY)
        "general/TestNGOverlayEmpty.xml#4.2", // failed: GEOMETRYCOLLECTION (POLYGON ((10 10, 10 30, 30 30, 30 10, 10 10)), LINESTRING EM
        "general/TestNGOverlayEmpty.xml#4.5", // failed: GEOMETRYCOLLECTION (POLYGON ((10 10, 10 30, 30 30, 30 10, 10 10)), LINESTRING EM
        "general/TestNGOverlayEmpty.xml#5.2", // failed: GEOMETRYCOLLECTION (POLYGON ((10 10, 10 30, 30 30, 30 10, 10 10)), POINT EMPTY)
        "general/TestNGOverlayEmpty.xml#5.5", // failed: GEOMETRYCOLLECTION (POLYGON ((10 10, 10 30, 30 30, 30 10, 10 10)), POINT EMPTY)
        "general/TestNGOverlayEmpty.xml#6.2", // failed: MULTILINESTRING ((10 10, 20 20), EMPTY)
        "general/TestNGOverlayEmpty.xml#6.5", // failed: MULTILINESTRING ((10 10, 20 20), EMPTY)
        "general/TestNGOverlayEmpty.xml#7.2", // failed: MULTILINESTRING (EMPTY, EMPTY)
        "general/TestNGOverlayEmpty.xml#8.2", // failed: GEOMETRYCOLLECTION (LINESTRING (10 10, 20 20), POINT EMPTY)
        "general/TestNGOverlayEmpty.xml#8.5", // failed: GEOMETRYCOLLECTION (LINESTRING (10 10, 20 20), POINT EMPTY)
        "general/TestNGOverlayEmpty.xml#9.2", // failed: GEOMETRYCOLLECTION (LINESTRING (10 10, 20 20), LINESTRING EMPTY, POINT EMPTY)
        "general/TestNGOverlayEmpty.xml#9.5", // failed: GEOMETRYCOLLECTION (LINESTRING (10 10, 20 20), LINESTRING EMPTY, POINT EMPTY)
        "general/TestOverlayAAPrec.xml#14.1", // failed: POLYGON ((180 120, 180 80, 160 80, 160 120, 160 160, 180 160, 180 120))
        "general/TestOverlayAAPrec.xml#5.1", // failed: POLYGON ((100 10, 90 10, 90 20, 90 30, 100 30, 100 20, 100 10))
        "general/TestOverlayEmpty.xml#1.2", // failed: MULTIPOINT (EMPTY, EMPTY)
        "general/TestOverlayEmpty.xml#103.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#104.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#105.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#13.2", // failed: GEOMETRYCOLLECTION (LINESTRING EMPTY, POINT EMPTY)
        "general/TestOverlayEmpty.xml#14.2", // failed: MULTILINESTRING (EMPTY, EMPTY)
        "general/TestOverlayEmpty.xml#15.2", // failed: GEOMETRYCOLLECTION (LINESTRING EMPTY, POLYGON EMPTY)
        "general/TestOverlayEmpty.xml#2.2", // failed: GEOMETRYCOLLECTION (POINT EMPTY, LINESTRING EMPTY)
        "general/TestOverlayEmpty.xml#21.2", // failed: LINESTRING EMPTY
        "general/TestOverlayEmpty.xml#25.2", // failed: GEOMETRYCOLLECTION (POLYGON EMPTY, POINT EMPTY)
        "general/TestOverlayEmpty.xml#26.2", // failed: GEOMETRYCOLLECTION (POLYGON EMPTY, LINESTRING EMPTY)
        "general/TestOverlayEmpty.xml#27.2", // failed: MULTIPOLYGON (EMPTY, EMPTY)
        "general/TestOverlayEmpty.xml#3.2", // failed: GEOMETRYCOLLECTION (POINT EMPTY, POLYGON EMPTY)
        "general/TestOverlayEmpty.xml#79.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#8.2", // failed: POINT EMPTY
        "general/TestOverlayEmpty.xml#80.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#81.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#85.2", // failed: POINT EMPTY
        "general/TestOverlayEmpty.xml#9.2", // failed: POINT EMPTY
        "general/TestOverlayEmpty.xml#91.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#92.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#93.2", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestOverlayEmpty.xml#97.2", // failed: POINT EMPTY
        "general/TestOverlayEmpty.xml#98.2", // failed: LINESTRING EMPTY
        "general/TestOverlayLLPrec.xml#1.2", // failed: MULTILINESTRING ((0 10, 400 10), (400 10, 620 10), (400 10, 0 11), (400 60, 400 
        "general/TestUnaryUnion.xml#14.1", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestUnaryUnion.xml#15.1", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestUnaryUnion.xml#16.1", // failed: GEOMETRYCOLLECTION EMPTY
        "general/TestUnaryUnion.xml#17.1", // failed: GEOMETRYCOLLECTION EMPTY
        "misc/TestOverlay.xml#1.1", // failed: POLYGON ((3097.3929252677053 -340.6343946513264, 2829.3203546600025 -1340.570480
        "misc/TestOverlay.xml#2.1", // failed: MULTIPOLYGON (((2.4053340052765395 48.862080185059575, 2.4060150535068257 48.862
        "misc/TestOverlay.xml#3.1", // failed: MULTIPOLYGON (((-200016.0237591756 257104.04485157225, -200014.23024947077 25710
        "misc/TestOverlay.xml#4.1", // failed: POLYGON ((-1120500.0000001257 851294.299192949, -1120500.0000001257 851299.81793
        "misc/TestOverlay.xml#5.1", // error: TopologyException: side location conflict at 374529.13289329654 4787774.49253090
        "misc/geos-bug838-union.xml#1.1", // failed: POLYGON ((945068.6 1937261.5, 945168.7000000001 1937262.3, 945368.9 1937264.1, 9
        "robust/TestRobustRelateFloat.xml#1.1", // failed: true
        "robust/overlay/TestOverlay-pg-list.xml#4.1", // failed: 3.310633523734671
        "validate/TestRelatePL.xml#2.7", // failed: true
    ]
}
