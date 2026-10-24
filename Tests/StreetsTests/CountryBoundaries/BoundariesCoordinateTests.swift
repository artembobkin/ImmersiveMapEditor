/// Tests of `LatLon` and `BoundingBox`, ported from the inline tests of `latlon.rs` and
/// `bbox.rs` of country-boundaries 1.2.0.

import Testing
@testable import CountryBoundaries

private func bboxThrows(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Bool {
    (try? BoundingBox(minLatitude: a, minLongitude: b, maxLatitude: c, maxLongitude: d)) == nil
}

@Suite struct BoundariesLatLonTests {
    @Test func returnErrors() {
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: -90.0001, longitude: 0) }
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: 90.0001, longitude: 0) }
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: .nan, longitude: 0) }
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: 0, longitude: .nan) }
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: .infinity, longitude: 0) }
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: 0, longitude: .infinity) }
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: -.infinity, longitude: 0) }
        #expect(throws: CountryBoundariesError.self) { try LatLon(latitude: 0, longitude: -.infinity) }
    }

    @Test func longitudeCanBeAnything() throws {
        _ = try LatLon(latitude: 0, longitude: 0)
        _ = try LatLon(latitude: 0, longitude: 180.1)
        _ = try LatLon(latitude: 0, longitude: 999999)
        _ = try LatLon(latitude: 0, longitude: -180.1)
        _ = try LatLon(latitude: 0, longitude: -99999)
    }
}

@Suite struct BoundariesBoundingBoxTests {
    @Test func returnErrors() {
        #expect(bboxThrows(-90.0001, 0, 0, 0))
        #expect(bboxThrows(90.0001, 0, 0, 0))
        #expect(bboxThrows(0, 0, -90.0001, 0))
        #expect(bboxThrows(0, 0, 90.0001, 0))

        #expect(bboxThrows(1.1, 0, 1.0, 0))

        #expect(bboxThrows(.nan, 0, 0, 0))
        #expect(bboxThrows(0, .nan, 0, 0))
        #expect(bboxThrows(0, 0, .nan, 0))
        #expect(bboxThrows(0, 0, 0, .nan))

        #expect(bboxThrows(.infinity, 0, 0, 0))
        #expect(bboxThrows(0, .infinity, 0, 0))
        #expect(bboxThrows(0, 0, .infinity, 0))
        #expect(bboxThrows(0, 0, 0, .infinity))

        #expect(bboxThrows(-.infinity, 0, 0, 0))
        #expect(bboxThrows(0, -.infinity, 0, 0))
        #expect(bboxThrows(0, 0, -.infinity, 0))
        #expect(bboxThrows(0, 0, 0, -.infinity))
    }

    @Test func returnBbox() {
        #expect(!bboxThrows(1.0, 0, 1.1, 0))
        #expect(!bboxThrows(-90, 0, 90, 0))
    }

    @Test func bboxMayHaveZeroSize() {
        #expect(!bboxThrows(0, 0, 0, 0))
    }

    @Test func bboxMayWrapAround180thMeridian() {
        #expect(!bboxThrows(0, 90, 0, -90))
    }

    @Test func longitudeCanBeAnything() {
        #expect(!bboxThrows(0, -180, 0, 0))
        #expect(!bboxThrows(0, -180, 0, 180))
        #expect(!bboxThrows(0, -720, 0, 999))
    }

    @Test func errorsAreCheckedInOrder() {
        #expect(throws: CountryBoundariesError.latitudeOutOfBounds(param: "min_latitude", latitude: 91)) {
            try BoundingBox(minLatitude: 91, minLongitude: .nan, maxLatitude: 92, maxLongitude: 0)
        }
        #expect(throws: CountryBoundariesError.minLatitudeGreaterThanMaxLatitude(minLatitude: 2, maxLatitude: 1)) {
            try BoundingBox(minLatitude: 2, minLongitude: .nan, maxLatitude: 1, maxLongitude: 0)
        }
    }
}
