/// The tests of geo 0.27's `area.rs`, `winding_order.rs` and `closest_point.rs`, and of the
/// polygon, line string and line cases of geo 0.28's `centroid.rs` (identical to 0.27's). The
/// `f32` closest point tests run in `f64`: every value in them is exact in both. The
/// numerical stability tests take the unit decagon from `unitDecagon`, since the tests do not
/// import Foundation for `cos` and `sin`.

import GeoAlgorithms
import Testing

@Suite struct AreaTests {
    @Test func areaEmptyPolygon() {
        #expect(approxRelativeEq(GeoPolygon(GeoLineString([]), []).signedArea, 0))
    }

    @Test func areaOnePointPolygon() {
        #expect(approxRelativeEq(geoPoly([(1, 0)]).signedArea, 0))
    }

    @Test func areaPolygon() {
        #expect(approxRelativeEq(geoPoly([(0, 0), (5, 0), (5, 6), (0, 6), (0, 0)]).signedArea, 30))
    }

    @Test func areaPolygonNumericalStability() {
        let polygon = GeoPolygon(GeoLineString(unitDecagon), [])
        let area = polygon.signedArea
        let shift = geoC(1.5e8, 1.5e8)
        let shifted = polygon.mapCoords { $0 + shift }
        let newArea = shifted.signedArea
        let err = abs(area - newArea) / area
        #expect(err < 1e-2)
    }

    @Test func rectangle() {
        #expect(approxRelativeEq(GeoRect(geoC(10, 30), geoC(20, 40)).signedArea, 100))
    }

    @Test func areaPolygonInner() {
        let polygon = geoPoly([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)], [
            [(1, 1), (2, 1), (2, 2), (1, 2), (1, 1)],
            [(5, 5), (6, 5), (6, 6), (5, 6), (5, 5)],
        ])
        #expect(approxRelativeEq(polygon.signedArea, 98))
    }

    @Test func areaMultipolygon() {
        let mpoly = GeoMultiPolygon([
            geoPoly([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)]),
            geoPoly([(1, 1), (2, 1), (2, 2), (1, 2), (1, 1)]),
            geoPoly([(5, 5), (6, 5), (6, 6), (5, 6), (5, 5)]),
        ])
        #expect(approxRelativeEq(mpoly.signedArea, 102))
    }

    @Test func areaLine() {
        #expect(approxRelativeEq(GeoLine(geoC(0, 0), geoC(1, 1)).signedArea, 0))
    }

    @Test func areaTriangle() {
        #expect(approxRelativeEq(GeoTriangle(geoC(0, 0), geoC(1, 0), geoC(0, 1)).signedArea, 0.5))
        #expect(approxRelativeEq(GeoTriangle(geoC(0, 0), geoC(0, 1), geoC(1, 0)).signedArea, -0.5))
    }

    @Test func areaMultiPolygonAreaReversed() {
        let polygonCW = geoPoly([(0, 0), (0, 1), (1, 1), (1, 0), (0, 0)])
        let polygonCCW = geoPoly([(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)])
        let polygonArea = polygonCW.unsignedArea
        let multiPolygon = GeoMultiPolygon([polygonCW, polygonCCW])
        #expect(polygonArea * 2 == multiPolygon.unsignedArea)
    }

    @Test func areaNorthAmericaCutout() {
        let polygon = GeoPolygon(geoLS(AreaFixtures.northAmericaExterior), AreaFixtures.northAmericaInteriors.map(geoLS))
        // The value is from Shapely.
        #expect(approxRelativeEq(polygon.unsignedArea, 0.006547948219252177, epsilon: Double.ulpOfOne, maxRelative: 0.0001))
    }
}

@Suite struct WindingTests {
    @Test func robustWindingFloat() {
        var lineString = geoLS([(0, 0), (2, 0), (1, 2)])
        // An open line string has no winding order.
        #expect(lineString.windingOrder == nil)
        lineString.coords.append(lineString.coords[0])
        #expect(lineString.windingOrder == .counterClockwise)
        lineString.makeCWWinding()
        #expect(lineString.windingOrder == .clockwise)
    }

    @Test func robustWindingInteger() {
        var lineString = geoLS([(0, 0), (2, 0), (1, 2)])
        #expect(lineString.windingOrder == nil)
        lineString.coords.append(lineString.coords[0])
        #expect(lineString.isCCW)
        let ccw = lineString.pointsCCW
        lineString.makeCWWinding()
        #expect(lineString.isCW)
        #expect(lineString.pointsCCW == ccw)
    }
}

@Suite struct CentroidTests {
    @Test func emptyLinestring() {
        #expect(GeoLineString([]).centroid == nil)
    }

    @Test func linestringOnePoint() {
        let coord = geoC(40.02, 116.34)
        #expect(GeoLineString([coord]).centroid == GeoPoint(coord))
    }

    @Test func linestring() {
        #expect(geoLS([(1, 1), (7, 1), (8, 1), (9, 1), (10, 1), (11, 1)]).centroid == geoP(6, 1))
    }

    @Test func linestringWithRepeatedPoint() {
        let l1 = geoLS([(1, 1), (1, 1), (1, 1)])
        #expect(l1.centroid == geoP(1, 1))
        let l2 = geoLS([(2, 2), (2, 2), (2, 2)])
        #expect(GeoMultiLineString([l1, l2]).centroid == geoP(1.5, 1.5))
    }

    @Test func emptyPolygon() {
        #expect(GeoPolygon(GeoLineString([]), []).centroid == nil)
    }

    @Test func polygonOnePoint() {
        let point = geoP(2, 1)
        let centroid = GeoPolygon(GeoLineString([point.coord]), []).centroid!
        #expect(approxRelativeEq(centroid.coord, point.coord))
    }

    @Test func centroidPolygonNumericalStability() {
        let polygon = GeoPolygon(GeoLineString(unitDecagon), [])
        let centroid = polygon.centroid!
        let shift = geoC(1.5e8, 1.5e8)
        let newCentroid = polygon.mapCoords { $0 + shift }.centroid!.mapCoords { $0 - shift }
        #expect(approxRelativeEq(centroid.x, newCentroid.x, maxRelative: 0.0001))
        #expect(approxRelativeEq(centroid.y, newCentroid.y, maxRelative: 0.0001))
    }

    @Test func polygon() {
        #expect(approxRelativeEq(geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)]).centroid!.coord, geoC(1, 1)))
    }

    @Test func polygonHole() {
        let p1 = GeoTestWKT.polygon("POLYGON((5.0 1.0,4.0 2.0,4.0 3.0,5.0 4.0,6.0 4.0,7.0 3.0,7.0 2.0,6.0 1.0,5.0 1.0),(5.0 1.3,5.5 2.0,6.0 1.3,5.0 1.3),(5.0 2.3,5.5 3.0,6.0 2.3,5.0 2.3))")
        #expect(approxRelativeEq(p1.centroid!.coord, geoC(5.5, 2.5518518518518523)))
    }

    @Test func flatPolygon() {
        #expect(GeoTestWKT.polygon("POLYGON((0. 1.,1. 1.,0. 1.))").centroid == geoP(0.5, 1))
    }

    @Test func multiPolyWithFlatPolygon() {
        #expect(GeoTestWKT.multiPolygon("MULTIPOLYGON(((0. 0.,1. 0.,0. 0.)))").centroid == geoP(0.5, 0))
    }

    @Test func multiPolyWithMultipleFlatPolygon() {
        #expect(GeoTestWKT.multiPolygon("MULTIPOLYGON(((1. 1.,1. 3.,1. 1.)),((2. 2.,6. 2.,2. 2.)))").centroid == geoP(3, 2))
    }

    @Test func multiPolyWithOnlyPoints() {
        #expect(GeoTestWKT.polygon("POLYGON((1. 1.,1. 1.,1. 1.))").centroid == geoP(1, 1))
        #expect(GeoTestWKT.multiPolygon("MULTIPOLYGON(((1. 1.,1. 1.,1. 1.)),((2. 2., 2. 2.,2. 2.)))").centroid == geoP(1.5, 1.5))
    }

    @Test func multiPolyWithOneRingAndOneRealPoly() {
        let normal = geoPoly([(1, 1), (1, 3), (3, 1), (1, 1)])
        let flat = geoPoly([(2, 2), (6, 2), (2, 2)])
        #expect(GeoMultiPolygon([normal, flat]).centroid == normal.centroid)
    }

    @Test func polygonFlatInterior() {
        let polygon = geoPoly([(0, 0), (0, 1), (1, 1), (1, 0), (0, 0)], [[(0, 0), (0, 1), (0, 0)]])
        #expect(polygon.centroid == geoP(0.5, 0.5))
    }

    @Test func emptyInteriorPolygon() {
        let polygon = GeoPolygon(geoLS([(0, 0), (0, 1), (1, 1), (1, 0), (0, 0)]), [GeoLineString([])])
        #expect(polygon.centroid == geoP(0.5, 0.5))
    }

    @Test func polygonRing() {
        let square = geoLS([(0, 0), (0, 1), (1, 1), (1, 0), (0, 0)])
        #expect(GeoPolygon(square, [square]).centroid == geoP(0.5, 0.5))
    }

    @Test func polygonCell() {
        let square = geoLS([(0, 0), (0, 2), (2, 2), (2, 0), (0, 0)])
        let bottom = geoLS([(0, 0), (2, 0), (2, 1), (0, 1), (0, 0)])
        let top = geoLS([(0, 1), (2, 1), (2, 2), (0, 2), (0, 1)])
        #expect(GeoPolygon(square, [top, bottom]).centroid == geoP(1, 1))
    }

    @Test func emptyMultipolygon() {
        #expect(GeoMultiPolygon([GeoPolygon]()).centroid == nil)
    }

    @Test func multipolygonOnePolygon() {
        #expect(GeoMultiPolygon([geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)])]).centroid == geoP(1, 1))
    }

    @Test func multipolygonTwoPolygons() {
        let mp = GeoMultiPolygon([
            geoPoly([(2, 1), (5, 1), (5, 3), (2, 3), (2, 1)]),
            geoPoly([(7, 1), (8, 1), (8, 2), (7, 2), (7, 1)]),
        ])
        #expect(approxRelativeEq(mp.centroid!.coord, geoC(4.071428571428571, 1.9285714285714286)))
    }

    @Test func multipolygonTwoPolygonsOfOppositeClockwise() {
        let mp = GeoMultiPolygon([
            geoPoly([(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)]),
            geoPoly([(0, 0), (-2, 0), (-2, 2), (0, 2), (0, 0)]),
        ])
        #expect(approxRelativeEq(mp.centroid!.coord, geoC(0, 1)))
    }

    @Test func boundingRect() {
        #expect(GeoRect(geoC(0, 50), geoC(4, 100)).centroid == geoP(2, 75))
    }

    @Test func line() {
        #expect(GeoLine(geoC(0, 1), geoC(1, 3)).centroid == geoP(0.5, 2))
    }
}
