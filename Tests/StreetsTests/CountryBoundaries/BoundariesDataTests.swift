/// Tests on the real boundary data: the embedded 60x30 raster, and the crate's own data files
/// when the crate is in the local cargo registry. Ported from `tests/integration_test.rs` and
/// the examples in the doc comments of `lib.rs` of country-boundaries 1.2.0, with points of
/// this project's own.

import Foundation
import Testing
@testable import CountryBoundaries

/// The data files of the crate in the local cargo registry.
private let crateData = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".cargo/registry/src/index.crates.io-1949cf8c6b5b557f/country-boundaries-1.2.0/data")

private func crateFile(_ name: String) -> URL {
    crateData.appendingPathComponent(name)
}

private func hasCrateFile(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: crateFile(name).path)
}

private func loadCrateFile(_ name: String) throws -> CountryBoundaries {
    try CountryBoundaries(data: Data(contentsOf: crateFile(name)))
}

private func latlon(_ latitude: Double, _ longitude: Double) throws -> LatLon {
    try LatLon(latitude: latitude, longitude: longitude)
}

/// The checks of `integration_test.rs`, run on the given data.
///
/// The crate's test expects `["BA"]` south of the Croatian border, but the data shipped with
/// 1.2.0 also has the entities of Bosnia and Herzegovina, so its own data gives the entity
/// first. The expectations here are what the data gives, the same for both rasters.
private func checkPoints(_ boundaries: CountryBoundaries) throws {
    // In clockwise order.
    #expect(boundaries.ids(try latlon(45.5, 16.0)) == ["HR"])
    #expect(boundaries.ids(try latlon(46.0, 16.0)) == ["HR"])
    #expect(boundaries.ids(try latlon(46.0, 16.5)) == ["HR"])
    #expect(boundaries.ids(try latlon(46.0, 17.0)) == ["HR"])
    #expect(boundaries.ids(try latlon(45.5, 17.0)) == ["HR"])

    #expect(boundaries.ids(try latlon(45.0, 17.0)) == ["BA-SRP", "BA"])
    #expect(boundaries.ids(try latlon(45.0, 16.5)) == ["BA-SRP", "BA"])
    #expect(boundaries.ids(try latlon(45.0, 16.0)) == ["BA-BIH", "BA"])

    // The point examples of the doc comments of `lib.rs`.
    #expect(boundaries.isIn(try latlon(47.6973, 8.6910), "DE"))
    #expect(!boundaries.isInAny(try latlon(21.0, 96.0), ["BD", "DJ", "IR", "PS"]))
    #expect(boundaries.ids(try latlon(33.0, -97.0)) == ["US-TX", "US"])
}

/// The box checks of `integration_test.rs` and of the doc comments of `lib.rs`, which hold for
/// the finer rasters of the crate (180x90 and 360x180).
private func checkBoxesOnFineRaster(_ boundaries: CountryBoundaries) throws {
    let wrapping = try BoundingBox(minLatitude: 66, minLongitude: 178, maxLatitude: 68, maxLongitude: -178)
    #expect(boundaries.containingIds(wrapping) == ["RU"])
    let bering = try BoundingBox(minLatitude: 50, minLongitude: 163, maxLatitude: 67, maxLongitude: -150)
    #expect(boundaries.intersectingIds(bering) == ["RU", "US-AK", "US"])
}

/// The same boxes on the 60x30 raster, whose cells are 6 degrees on a side: the cells around
/// the wrapping box hold sea and Alaska too, so no region contains them all, and the cells of
/// the Bering box reach into Yakutia.
private func checkBoxesOn60x30(_ boundaries: CountryBoundaries) throws {
    let wrapping = try BoundingBox(minLatitude: 66, minLongitude: 178, maxLatitude: 68, maxLongitude: -178)
    #expect(boundaries.containingIds(wrapping).isEmpty)
    let bering = try BoundingBox(minLatitude: 50, minLongitude: 163, maxLatitude: 67, maxLongitude: -150)
    #expect(boundaries.intersectingIds(bering) == ["RU-SA", "RU", "US-AK", "US"])
}

@Suite struct BoundariesDataTests {
    @Test func embeddedDataIsTheCrateFile() throws {
        let embedded = CountryBoundaries.odbl60x30
        #expect(embedded.rasterWidth == 60)
        #expect(embedded.raster.count == 1800)
        #expect(embedded.geometrySizes.count == 516)
        if hasCrateFile("boundaries60x30.ser") {
            #expect(try loadCrateFile("boundaries60x30.ser") == embedded)
        }
    }

    @Test func examplesOnEmbedded60x30() throws {
        try checkPoints(CountryBoundaries.odbl60x30)
        try checkBoxesOn60x30(CountryBoundaries.odbl60x30)
    }

    @Test(.enabled(if: hasCrateFile("boundaries180x90.ser")))
    func examplesOnCrate180x90() throws {
        let boundaries = try loadCrateFile("boundaries180x90.ser")
        try checkPoints(boundaries)
        try checkBoxesOnFineRaster(boundaries)
    }

    @Test(.enabled(if: hasCrateFile("boundaries360x180.ser")))
    func examplesOnCrate360x180() throws {
        let boundaries = try loadCrateFile("boundaries360x180.ser")
        try checkPoints(boundaries)
        try checkBoxesOnFineRaster(boundaries)
    }

    @Test(arguments: [
        (55.7539, 37.6208, ["RU"]),
        (47.6, -122.3, ["US-WA", "US"]),
        (51.5, -0.12, ["GB-ENG", "GB"]),
        (52.5, 13.4, ["DE"]),
        (-31.95, 115.86, ["AU-WA", "AU"]),
        (25.03, 121.56, ["TW"]),
        (17.71, -64.88, ["VI", "US"]),
        (33.42, -111.94, ["US-AZ", "US"]),
    ])
    func idsAtRealPoints(latitude: Double, longitude: Double, expected: [String]) throws {
        #expect(CountryBoundaries.odbl60x30.ids(try latlon(latitude, longitude)) == expected)
    }

    @Test func lazyDataIsSharedAcrossThreads() async throws {
        let moscow = try latlon(55.7539, 37.6208)
        let results = await withTaskGroup(of: [String].self) { group in
            for _ in 0..<8 {
                group.addTask { CountryBoundaries.odbl60x30.ids(moscow) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results == Array(repeating: ["RU"], count: 8))
    }
}
