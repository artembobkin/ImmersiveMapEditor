/// Parity of the Swift osm2streets with the Rust binary on osm2streets's own
/// test cases and on the Moscow data of the pipeline. Skips when the binary
/// or the cases are missing. Each case's summary is printed. Also the committed
/// `geometry.json` of osm2streets's tests, against the port alone.

import Foundation
import StreetGeom
import Streets
import Testing

@Suite(.serialized, .enabled(if: Oracle.available, "the Rust osm2streets-cli is not built"))
struct StreetsParityTests {
    static let cases: [String] = (try? FileManager.default.contentsOfDirectory(atPath: Oracle.testsDir.path))?
        .filter { FileManager.default.fileExists(atPath: Oracle.testsDir.appendingPathComponent("\($0)/input.osm").path) }
        .sorted() ?? []

    @Test(arguments: cases)
    func osm2streetsCase(_ name: String) throws {
        let dir = Oracle.testsDir.appendingPathComponent(name)
        let clip = dir.appendingPathComponent("boundary.json")
        let run = try ParityRun.run(name: name, input: dir.appendingPathComponent("input.osm"),
                                    clip: FileManager.default.fileExists(atPath: clip.path) ? clip : nil)
        print("PARITY \(run.summary)")
        #expect(run.allMatch, "\(run.summary)")
    }

    /// The committed `geometry.json` of osm2streets's tests, made as its
    /// tests make it: the default configuration (no inferred sidewalks),
    /// invariants checked, the transformations for clipped areas.
    @Test(arguments: cases)
    func committedGeometry(_ name: String) throws {
        let dir = Oracle.testsDir.appendingPathComponent(name)
        let expectedURL = dir.appendingPathComponent("geometry.json")
        guard FileManager.default.fileExists(atPath: expectedURL.path) else { return }
        let clipURL = dir.appendingPathComponent("boundary.json")
        let clip = try FileManager.default.fileExists(atPath: clipURL.path)
            ? LonLat.parseGeoJSONPolygons(String(contentsOf: clipURL, encoding: .utf8))[0].0 : nil
        var streets = try StreetNetwork.fromOSM(Array(try Data(contentsOf: dir.appendingPathComponent("input.osm"))),
                                                clip: clip, config: MapConfig())
        streets.checkInvariants()
        streets.applyTransformationsWithInvariantChecks(Transformation.standardForClippedAreas())
        let actual = streets.toGeoJSON(.all)
        let expected = try String(contentsOf: expectedURL, encoding: .utf8)
        let c = GeoJSONComparison.compare(expected: expected, actual: actual)
        print("GEOMETRY \(name): \(c.featuresActual)/\(c.featuresExpected) features, "
              + (c.identicalText ? "identical" : (c.matches ? "equal within 1e-9" : "differs at \(c.firstDifference!)")))
        #expect(c.identicalText, "\(c.firstDifference ?? "")")
    }

    static let region = Oracle.tilePipelineData.appendingPathComponent("regions/15_19808_10242_19809_10243")
    static let tiles = ["15_19808_10242", "15_19809_10242", "15_19808_10243", "15_19809_10243", "15_19810_10243"]
        .filter { FileManager.default.fileExists(atPath: Oracle.tilePipelineData.appendingPathComponent("\($0)/osm.json").path) }

    /// The 2x2 block the pipeline seeds, with the clip it seeds it with.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: region.appendingPathComponent("osm.json").path)))
    func moscowRegion() throws {
        let input = try moscowXML(Self.region.appendingPathComponent("osm.json"), name: "moscow_region")
        let run = try ParityRun.run(name: "moscow_region", input: input,
                                    clip: Self.region.appendingPathComponent("streets/clip.geojson"))
        print("PARITY \(run.summary)")
        #expect(run.allMatch, "\(run.summary)")
    }

    /// Each tile's own OSM, unclipped.
    @Test(arguments: tiles)
    func moscowTile(_ tile: String) throws {
        let input = try moscowXML(Oracle.tilePipelineData.appendingPathComponent("\(tile)/osm.json"), name: "moscow_\(tile)")
        let run = try ParityRun.run(name: "moscow_\(tile)", input: input, clip: nil)
        print("PARITY \(run.summary)")
        #expect(run.allMatch, "\(run.summary)")
    }

    private func moscowXML(_ json: URL, name: String) throws -> URL {
        let out = Oracle.scratch.appendingPathComponent("\(name).osm")
        try FileManager.default.createDirectory(at: Oracle.scratch, withIntermediateDirectories: true)
        try OverpassXML.convert(Data(contentsOf: json)).write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}
