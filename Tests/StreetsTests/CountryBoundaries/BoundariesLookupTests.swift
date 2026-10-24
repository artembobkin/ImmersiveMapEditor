/// Tests of the raster lookups on small hand-made worlds, ported from the inline tests of
/// `lib.rs` of country-boundaries 1.2.0.

import Testing
@testable import CountryBoundaries

private func cell(_ containingIds: [String]) -> Cell {
    Cell(containingIds: containingIds, intersectingAreas: [])
}

private func latlon(_ latitude: Double, _ longitude: Double) throws -> LatLon {
    try LatLon(latitude: latitude, longitude: longitude)
}

private func bbox(_ minLat: Double, _ minLon: Double, _ maxLat: Double, _ maxLon: Double) throws -> BoundingBox {
    try BoundingBox(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
}

@Suite struct BoundariesLookupTests {
    @Test func delegatesToCorrectCellAtEdges() throws {
        // The world:
        // +-+-+
        // |A|B|
        // +-+-+
        // |C|D|
        // +-+-+
        let boundaries = CountryBoundaries(
            raster: [cell(["A"]), cell(["B"]), cell(["C"]), cell(["D"])], rasterWidth: 2, geometrySizes: [:])

        #expect(boundaries.ids(try latlon(-90, -180)) == ["C"])
        #expect(boundaries.ids(try latlon(-90, -90)) == ["C"])
        #expect(boundaries.ids(try latlon(-45, -180)) == ["C"])
        // It wraps around.
        #expect(boundaries.ids(try latlon(-45, 180)) == ["C"])
        #expect(boundaries.ids(try latlon(-90, 180)) == ["C"])

        #expect(boundaries.ids(try latlon(0, -180)) == ["A"])
        #expect(boundaries.ids(try latlon(45, -180)) == ["A"])
        #expect(boundaries.ids(try latlon(0, -90)) == ["A"])
        // It wraps around.
        #expect(boundaries.ids(try latlon(0, 180)) == ["A"])
        #expect(boundaries.ids(try latlon(45, 180)) == ["A"])

        #expect(boundaries.ids(try latlon(0, 0)) == ["B"])
        #expect(boundaries.ids(try latlon(45, 0)) == ["B"])
        #expect(boundaries.ids(try latlon(0, 90)) == ["B"])

        #expect(boundaries.ids(try latlon(-45, 0)) == ["D"])
        #expect(boundaries.ids(try latlon(-90, 0)) == ["D"])
        #expect(boundaries.ids(try latlon(-90, 90)) == ["D"])
    }

    @Test func noArrayIndexOutOfBoundsAtWorldEdges() throws {
        let boundaries = CountryBoundaries(raster: [cell(["A"])], rasterWidth: 1, geometrySizes: [:])
        _ = boundaries.ids(try latlon(-90, -180))
        _ = boundaries.ids(try latlon(90, 180))
        _ = boundaries.ids(try latlon(90, -180))
        _ = boundaries.ids(try latlon(-90, 180))
    }

    @Test func getContainingIdsSortedBySizeAscending() throws {
        let boundaries = CountryBoundaries(
            raster: [cell(["D", "B", "C", "A"])],
            rasterWidth: 1,
            geometrySizes: ["A": 10, "B": 15, "C": 100, "D": 800]
        )
        #expect(boundaries.ids(try latlon(1, 1)) == ["A", "B", "C", "D"])
    }

    @Test func idsOfEqualSizeKeepTheOrderOfTheCell() throws {
        // The crate's sort is stable, and a region missing from the sizes counts as 0.
        let boundaries = CountryBoundaries(
            raster: [cell(["D", "B", "X", "C", "A", "Y"])],
            rasterWidth: 1,
            geometrySizes: ["A": 10, "B": 15, "C": 10, "D": 15]
        )
        #expect(boundaries.ids(try latlon(1, 1)) == ["X", "Y", "C", "A", "D", "B"])
    }

    @Test func getIntersectingIdsInBboxIsMergedCorrectly() throws {
        let boundaries = CountryBoundaries(
            raster: [cell(["A"]), cell(["B"]), cell(["C"]), cell(["D", "E"])], rasterWidth: 2, geometrySizes: [:])
        #expect(boundaries.intersectingIds(try bbox(-10, -10, 10, 10)) == ["A", "B", "C", "D", "E"])
    }

    @Test func getIntersectingIdsInBboxWrapsLongitudeCorrectly() throws {
        let boundaries = CountryBoundaries(
            raster: [cell(["A"]), cell(["B"]), cell(["C"])], rasterWidth: 3, geometrySizes: [:])
        #expect(boundaries.intersectingIds(try bbox(0, 170, 1, -170)) == ["A", "C"])
    }

    @Test func getContainingIdsInBboxWrapsLongitudeCorrectly() throws {
        let boundaries = CountryBoundaries(
            raster: [cell(["A", "B", "C"]), cell(["X"]), cell(["A", "B"])], rasterWidth: 3, geometrySizes: [:])
        #expect(boundaries.containingIds(try bbox(0, 170, 1, -170)) == ["A", "B"])
    }

    @Test func getContainingIdsInBboxReturnsCorrectResultWhenOneCellIsEmpty() throws {
        let boundaries = CountryBoundaries(
            raster: [cell([]), cell(["A"]), cell(["A"]), cell(["A"])], rasterWidth: 2, geometrySizes: [:])
        #expect(boundaries.containingIds(try bbox(-10, -10, 10, 10)).isEmpty)
    }

    @Test func getContainingIdsInBboxIsMergedCorrectly() throws {
        let boundaries = CountryBoundaries(
            raster: [cell(["A", "B"]), cell(["B", "A"]), cell(["C", "B", "A"]), cell(["D", "A"])],
            rasterWidth: 2,
            geometrySizes: [:]
        )
        #expect(boundaries.containingIds(try bbox(-10, -10, 10, 10)) == ["A"])
    }

    @Test func getContainingIdsInBboxIsMergedCorrectlyAndNothingIsLeft() throws {
        let boundaries = CountryBoundaries(
            raster: [cell(["A"]), cell(["B"]), cell(["C"]), cell(["D"])], rasterWidth: 2, geometrySizes: [:])
        #expect(boundaries.containingIds(try bbox(-10, -10, 10, 10)).isEmpty)
    }

    @Test func numbersConvertAsInRust() {
        #expect(normalize(540, startAt: -180, base: 360) == 180 - 360)
        #expect(normalize(-190, startAt: -180, base: 360) == 170)
        #expect(normalize(180, startAt: -180, base: 360) == -180)
        #expect(saturatingInt(-0.5) == 0)
        #expect(saturatingInt(.nan) == 0)
        #expect(saturatingUInt16(65535.9) == 65535)
        #expect(saturatingUInt16(70000) == 65535)
        #expect(saturatingUInt16(12.9) == 12)
        #expect(totalOrderKey(-0.0) < totalOrderKey(0.0))
        #expect(totalOrderKey(-1.0) < totalOrderKey(-0.5))
        #expect(totalOrderKey(1.0) < totalOrderKey(.infinity))
    }
}
