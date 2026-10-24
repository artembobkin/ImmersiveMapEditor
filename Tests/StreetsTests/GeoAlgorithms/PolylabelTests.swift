/// The tests of polylabel 3.2.0 (`src/lib.rs`), with its polygon fixtures embedded.

import GeoAlgorithms
import Testing

@Suite struct PolylabelTests {
    @Test func polylabelShapely() throws {
        // The polygons of Shapely's tests.
        let polygon = geoPoly(PolylabelFixtures.poly1)
        #expect(try polylabel(polygon, tolerance: 10.000) == geoP(59.35615556364569, 121.83919629746435))
    }

    @Test func concave() throws {
        // The centroid of this concave polygon lies outside it: the label must not.
        let polygon = geoPoly(PolylabelFixtures.poly2)
        #expect(polygon.contains(try polylabel(polygon, tolerance: 1.0)))
    }

    @Test func london() throws {
        let polygon = geoPoly(PolylabelFixtures.poly3)
        #expect(try polylabel(polygon, tolerance: 0.001) == geoP(-0.45556816445920356, 51.54848888202887))
    }

    @Test func polygonL() throws {
        let polygon = geoPoly([(0, 0), (4, 0), (4, 1), (1, 1), (1, 4), (0, 4), (0, 0)])
        #expect(try polylabel(polygon, tolerance: 0.10) == geoP(0.5625, 0.5625))
    }

    @Test func degeneratePolygon() throws {
        let polygon = geoPoly([(0, 0), (1, 0), (2, 0), (0, 0)])
        #expect(try polylabel(polygon, tolerance: 1.0) == geoP(0, 0))
    }

    @Test func degeneratePolygon2() throws {
        let polygon = geoPoly([(0, 0), (1, 0), (1, 1), (1, 0), (0, 0)])
        #expect(try polylabel(polygon, tolerance: 1.0) == geoP(0, 0))
    }
}
