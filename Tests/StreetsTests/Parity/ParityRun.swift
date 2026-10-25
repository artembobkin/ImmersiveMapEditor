/// One parity case: the Rust binary and the Swift port over the same OSM
/// file and clip, their four GeoJSON outputs compared.
///
/// The Rust is not always deterministic: streets_reader iterates traffic
/// signals and crossings in `HashMap` order, random per process, and when two
/// of them set the same road end the last one wins. The port records those
/// road ends (`HashMapOrder`) and computes its result for every choice of the
/// last one at each. A case passes when every Rust run (16 where the order
/// changes the result, else one) equals one of the port's results: its order
/// is reproduced exactly, so the test does not depend on which orders the
/// Rust happens to take.

import Foundation
import StreetGeom
@testable import Streets

struct ParityRun {
    var name: String
    /// The port's time, from reading the OSM to the four outputs.
    var seconds = 0.0
    var comparisons: [String: GeoJSONComparison] = [:]
    var tagSets = 0
    var roads = 0
    var intersections = 0
    /// Road ends where the order of the Rust's HashMaps decides the result.
    var contestedEnds = 0
    var contestedDetail: [String] = []
    /// The port's distinct results over every such order.
    var portVariants = 1
    /// Distinct Rust results seen, and in how many runs.
    var rustVariants = 1
    var rustRuns = 1
    /// Every Rust run equals the port's result for one of the orders.
    var everyRustRunExplained = false

    var allMatch: Bool { everyRustRunExplained }

    /// The pipeline's configuration: inferred sidewalks and kerbs.
    static func pipelineConfig() -> MapConfig {
        var cfg = MapConfig()
        cfg.inferredSidewalks = true
        cfg.inferredKerbs = true
        return cfg
    }

    /// The four outputs of the port, the signals and crossings applied in `order`.
    static func portOutputs(_ bytes: [UInt8], _ clipPts: [LonLat]?, _ config: MapConfig,
                            _ order: HashMapOrder) throws -> (StreetNetwork, [String]) {
        var streets = try StreetNetwork.fromOSM(bytes, clip: clipPts, config: config, hashMapOrder: order)
        streets.applyTransformations(Transformation.standardForClippedAreas())
        return (streets, [streets.toGeoJSON(.all), streets.toLanePolygonsGeoJSON(.all),
                          try streets.toLaneMarkingsGeoJSON(.all), streets.toIntersectionMarkingsGeoJSON(.all)])
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
        let order = HashMapOrder()
        let (streets, outputs) = try portOutputs(bytes, clipPts, config, order)
        let elapsed = clock.now - started
        let actual = Dictionary(uniqueKeysWithValues: zip(Oracle.outputs, outputs))
        let swiftDir = work.appendingPathComponent("swift")
        try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)
        var result = ParityRun(name: name, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18,
                               tagSets: tagSets, roads: streets.roads.count,
                               intersections: streets.intersections.count)
        for k in Oracle.outputs {
            try actual[k]!.write(to: swiftDir.appendingPathComponent("\(k).geojson"), atomically: true, encoding: .utf8)
            result.comparisons[k] = GeoJSONComparison.compare(expected: expected[k]!, actual: actual[k]!)
        }

        // Every order the Rust's HashMaps can take: for each road end that
        // several signals, or several crossings, set, each of them last.
        let contested = order.contested
        result.contestedEnds = contested.count
        result.contestedDetail = contested.map { g, pts in
            "\(g.map) at the \(g.atEnd ? "end" : "start") of \(g.road) (\(pts.count) points, way \(streets.roads[g.road].map { "\($0.osmIDs.map(\.id))" } ?? "removed"))"
        }
        var portVariants: Set<[String]> = [outputs]
        if !contested.isEmpty {
            let combinations = contested.reduce(1) { $0 * $1.1.count }
            precondition(combinations <= 4096, "\(combinations) orders to try")
            for c in 0..<combinations {
                var rest = c
                let o = HashMapOrder()
                for (group, pts) in contested {
                    let pt = pts[rest % pts.count]
                    rest /= pts.count
                    if group.map == "signals" { o.signalsLast.insert(pt) } else { o.crossingsLast.insert(pt) }
                }
                portVariants.insert(try portOutputs(bytes, clipPts, config, o).1)
            }
        }
        result.portVariants = portVariants.count

        // The Rust's runs must each be one of those: its order reproduced,
        // not hoped for. Where the order changes the result, the Rust runs
        // 16 times.
        let first = Oracle.outputs.map { expected[$0]! }
        var rustVariants: Set<[String]> = [first]
        var explained = portVariants.contains(first)
        if portVariants.count > 1 || !explained {
            for k in 2...16 {
                let again = try Oracle.run(input: input, clip: clip, out: work.appendingPathComponent("rust\(k)"))
                let a = Oracle.outputs.map { again[$0]! }
                rustVariants.insert(a)
                explained = explained && portVariants.contains(a)
                result.rustRuns = k
            }
        }
        result.rustVariants = rustVariants.count
        result.everyRustRunExplained = explained
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
        if contestedEnds > 0 || rustRuns > 1 {
            s += "; \(contestedEnds) road ends set by several signals or crossings (\(contestedDetail.joined(separator: ", "))), \(portVariants) port results over their orders, "
            s += "the Rust gave \(rustVariants) distinct results in \(rustRuns) runs, "
            s += everyRustRunExplained ? "each one of the port's" : "not all of them the port's"
        }
        return s
    }
}
