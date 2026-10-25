/// One parity case: the Rust binary and the Swift port over the same OSM
/// file and clip, their four GeoJSON outputs compared.
///
/// The Rust is not always deterministic: streets_reader iterates traffic
/// signals and crossings in `HashMap` order, random per process, and when two
/// of them set the same road end the last one wins. When the first Rust run
/// differs from the port, the case runs the Rust again (16 runs in all) and
/// passes only if the port's four outputs equal those of one of the runs.

import Foundation
import StreetGeom
import Streets

struct ParityRun {
    var name: String
    /// The port's time, from reading the OSM to the four outputs.
    var seconds = 0.0
    var comparisons: [String: GeoJSONComparison] = [:]
    var tagSets = 0
    var roads = 0
    var intersections = 0
    /// Distinct Rust results seen, when the first one did not match.
    var rustVariants = 1
    var rustRuns = 1
    var matchedVariant = false

    var allMatch: Bool { matchedVariant || Oracle.outputs.allSatisfy { comparisons[$0]?.matches == true } }

    /// The pipeline's configuration: inferred sidewalks and kerbs.
    static func pipelineConfig() -> MapConfig {
        var cfg = MapConfig()
        cfg.inferredSidewalks = true
        cfg.inferredKerbs = true
        return cfg
    }

    static func run(name: String, input: URL, clip: URL?) throws -> ParityRun {
        let work = Oracle.scratch.appendingPathComponent(name)
        let expected = try Oracle.run(input: input, clip: clip, out: work.appendingPathComponent("rust"))
        let bytes = Array(try Data(contentsOf: input))
        let clipPts = try clip.map { url -> [LonLat] in
            let polygons = try LonLat.parseGeoJSONPolygons(String(contentsOf: url, encoding: .utf8))
            precondition(polygons.count == 1, "the clip GeoJSON must hold exactly one polygon")
            return polygons[0].0
        }
        let config = pipelineConfig()
        let tagSets = try RoadWays.collect(bytes, clip: clipPts, config: config).tagSets.count
        let clock = ContinuousClock()
        let started = clock.now
        var streets = try StreetNetwork.fromOSM(bytes, clip: clipPts, config: config)
        streets.applyTransformations(Transformation.standardForClippedAreas())
        let actual = [
            "plain": streets.toGeoJSON(.all),
            "lanes": streets.toLanePolygonsGeoJSON(.all),
            "lane_markings": try streets.toLaneMarkingsGeoJSON(.all),
            "intersection_markings": streets.toIntersectionMarkingsGeoJSON(.all),
        ]
        let elapsed = clock.now - started
        let swiftDir = work.appendingPathComponent("swift")
        try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)
        var result = ParityRun(name: name, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18,
                               tagSets: tagSets, roads: streets.roads.count,
                               intersections: streets.intersections.count)
        for k in Oracle.outputs {
            try actual[k]!.write(to: swiftDir.appendingPathComponent("\(k).geojson"), atomically: true, encoding: .utf8)
            result.comparisons[k] = GeoJSONComparison.compare(expected: expected[k]!, actual: actual[k]!)
        }
        if !result.allMatch {
            var variants: Set<[String]> = [Oracle.outputs.map { expected[$0]! }]
            for k in 2...16 {
                let again = try Oracle.run(input: input, clip: clip, out: work.appendingPathComponent("rust\(k)"))
                variants.insert(Oracle.outputs.map { again[$0]! })
                result.rustRuns = k
            }
            result.rustVariants = variants.count
            result.matchedVariant = variants.contains(Oracle.outputs.map { actual[$0]! })
        }
        return result
    }

    var summary: String {
        var s = "\(name) (\(String(format: "%.2f", seconds)) s): \(roads) roads, \(intersections) intersections, \(tagSets) tag sets"
        for k in Oracle.outputs {
            let c = comparisons[k]!
            s += "; \(k) \(c.featuresActual)/\(c.featuresExpected) features, "
            s += c.identicalText ? "identical" : (c.matches ? "equal within 1e-9 (\(c.numbersWithinTolerance) numbers)"
                : "differs from the first Rust run at \(c.firstDifference!)")
        }
        if rustRuns > 1 {
            s += "; the Rust gave \(rustVariants) distinct results in \(rustRuns) runs, "
            s += matchedVariant ? "the port's is one of them" : "the port's is none of them"
        }
        return s
    }
}
