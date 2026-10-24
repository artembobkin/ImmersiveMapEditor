/// The port of earcutr 0.4.3's `tests/integration_test.rs`: the inline cases and the fixture
/// cases with their expected triangle counts and deviations. Each fixture is also checked to give
/// exactly the triangles the crate's own test run recorded in `viz/testoutput/`.

import Earcut
import Testing

/// Triangulates a fixture as the crate's `area_test` does, checks its triangle count and deviation
/// against the expected ones, and returns the triangles.
private func checkArea(_ fixture: FixtureCase, _ data: [[[Double]]]) throws -> [Int] {
    let expectedDeviation = fixture.deviation == 0.0 ? 1e-14 : fixture.deviation
    let (vertices, holeIndices, dimensions) = Earcut.flatten(data)
    let triangles = try Earcut.earcut(vertices, holeIndices: holeIndices, dimensions: dimensions)
    let actualTriangles = triangles.count / 3
    let actualDeviation = Earcut.deviation(
        vertices, holeIndices: holeIndices, dimensions: dimensions, triangles: triangles
    )
    #expect(
        !(fixture.triangles > 0 && fixture.triangles < actualTriangles),
        "\(fixture.name): \(actualTriangles) triangles, expected at most \(fixture.triangles)"
    )
    #expect(
        !(expectedDeviation < actualDeviation),
        "\(fixture.name): deviation \(actualDeviation), expected at most \(expectedDeviation)"
    )
    return triangles
}

@Suite("earcutr integration tests")
struct EarcutIntegrationTests {
    @Test func indices2D() throws {
        let indices = try Earcut.earcut(
            [10.0, 0.0, 0.0, 50.0, 60.0, 60.0, 70.0, 10.0], holeIndices: [], dimensions: 2
        )
        #expect(indices == [1, 0, 3, 3, 2, 1])
    }

    @Test func empty() throws {
        let indices = try Earcut.earcut([], holeIndices: [], dimensions: 2)
        #expect(indices.isEmpty)
    }

    @Test("Embedded fixture", arguments: embeddedFixtureCases)
    func embeddedFixture(_ fixture: FixtureCase) throws {
        let data = try #require(loadFixture(fixture.name), "cannot parse \(fixture.name)")
        let triangles = try checkArea(fixture, data)
        #expect(triangles == embeddedRecordedTriangles[fixture.name])
    }

    @Test(
        "Fixture from the cargo registry",
        .enabled(if: earcutrFixturesAvailable, "the earcutr 0.4.3 crate is not in ~/.cargo"),
        arguments: onDiskFixtureCases
    )
    func onDiskFixture(_ fixture: FixtureCase) throws {
        let data = try #require(loadFixture(fixture.name), "cannot read \(fixture.name)")
        let triangles = try checkArea(fixture, data)
        let recorded = try #require(
            loadRecordedTriangles(fixture.name), "no recorded output for \(fixture.name)"
        )
        #expect(triangles == recorded)
    }

    /// The embedded recorded triangles agree with the crate's files they were copied from.
    @Test(
        "Embedded recorded triangles match the crate's files",
        .enabled(if: earcutrFixturesAvailable, "the earcutr 0.4.3 crate is not in ~/.cargo"),
        arguments: embeddedFixtureCases
    )
    func embeddedRecordsMatchFiles(_ fixture: FixtureCase) {
        #expect(embeddedRecordedTriangles[fixture.name] == loadRecordedTriangles(fixture.name))
    }
}
