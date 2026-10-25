/// MuvLanes against the Rust: synthetic ways with a wide set of tag sets
/// (written by hand to reach every part of Muv's lane reading, and drawn at
/// random from a vocabulary of lane keys with a fixed seed) in boxes in
/// several countries, read by the Rust osm2streets and by the port. The
/// four outputs must be identical, the lanes (with their `muv` property,
/// Muv's serde output) above all. Skips when the Rust binary is missing.

import Foundation
import Testing

@Suite(.serialized, .enabled(if: Oracle.available, "the Rust osm2streets-cli is not built"))
struct MuvLanesOracleTests {
    static let boxes: [SyntheticBox] = [
        .around("RU", lon: 37.61, lat: 55.75),
        .around("DE", lon: 13.40, lat: 52.52),
        .around("GB", lon: -0.12, lat: 51.50),
        .around("US", lon: -74.00, lat: 40.71),
        .around("FR", lon: 2.35, lat: 48.85),
        .around("NL", lon: 4.90, lat: 52.37),
        .around("IE", lon: -6.26, lat: 53.35),
        .around("AU", lon: 151.21, lat: -33.87),
        .around("AT", lon: 16.37, lat: 48.21),
        .around("BE", lon: 4.35, lat: 50.85),
    ]

    @Test(arguments: boxes)
    func handWritten(_ box: SyntheticBox) throws {
        let r = try SyntheticWays.compare(MuvTagSets.handWritten, in: box,
                                          work: Oracle.scratch.appendingPathComponent("muv_hand_\(box.name)"))
        print("MUV hand-written \(box.name): \(MuvTagSets.handWritten.count) tag sets, \(r.lanes) lanes, \(r.outputsIdentical)")
        #expect(r.allIdentical, "\(r.firstDifference ?? "no lane differs")")
    }

    @Test(arguments: boxes)
    func random(_ box: SyntheticBox) throws {
        var sets = MuvTagSets.random(count: 400, seed: box.name.utf8.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1) })
        let work = Oracle.scratch.appendingPathComponent("muv_random_\(box.name)")
        // A random way can make the Rust itself panic (geom's `dist_along` of
        // a negative distance): such ways, found one by one, are left out
        // and listed. The port is not run on them, a panic having no output.
        var rejected = Set<Int>()
        let r: SyntheticWays.Result
        do {
            r = try SyntheticWays.compare(sets, in: box, work: work)
        } catch OracleError.failed {
            rejected = try SyntheticWays.rustRejected(sets, in: box, work: work.appendingPathComponent("alone"))
            sets = sets.enumerated().filter { !rejected.contains($0.offset) }.map(\.element)
            r = try SyntheticWays.compare(sets, in: box, work: work)
        }
        print("MUV random \(box.name): \(sets.count) tag sets, \(r.lanes) lanes, \(r.outputsIdentical); "
              + "left out as the Rust panics: \(rejected.count)")
        #expect(r.allIdentical, "\(r.firstDifference ?? "no lane differs")")
    }
}

extension SyntheticBox: CustomTestStringConvertible {
    var testDescription: String { name }
}
