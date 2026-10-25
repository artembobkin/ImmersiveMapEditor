import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// The recorded predicate calls of `Geometry` replayed on the port and on
/// GEOS: `intersects`, `contains`, `within`, and the prepared geometries'
/// `contains` and `intersects` (each recorded `Prepared.init` prepared on
/// both sides, its later calls replayed against it). Every answer equal;
/// the time each side takes is printed. Long: run with
/// `TOPOLOGY_LONG_REPLAY=1`, best in a release build.
@Suite(.enabled(if: Recording.longReplay, "long replays run with TOPOLOGY_LONG_REPLAY=1 and the recordings in .build/recording"))
struct PredicateReplayTests {
    static func replay(_ name: String, _ mine: (Topology.Geometry, Topology.Geometry) throws -> Bool,
                       _ theirs: (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> Int8) {
        var tally = ParityTally("replay \(name)")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        let o = GEOSOracle()
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            for c in r.calls where c.name == name {
                let a = inputs.port(c.geometries[0]), b = inputs.port(c.geometries[1])
                let ga = inputs.geos(c.geometries[0]), gb = inputs.geos(c.geometries[1])
                var g: Bool?
                time.geos += clock.measure { g = ga.predicate(gb, theirs) }
                var m: Bool?
                time.port += clock.measure { m = try? mine(a, b) }
                tally.check(m == g, "\(r.name) #\(c.geometries): port \(String(describing: m)) GEOS \(String(describing: g))")
            }
        }
        tally.report()
        time.report(name)
    }

    @Test func intersects() { PredicateReplayTests.replay("intersects", { try $0.intersects($1) }, GEOSIntersects_r) }
    @Test func contains() { PredicateReplayTests.replay("contains", { try $0.contains($1) }, GEOSContains_r) }
    @Test func within() { PredicateReplayTests.replay("within", { try $0.within($1) }, GEOSWithin_r) }

    @Test func prepared() {
        var contains = ParityTally("replay Prepared.contains")
        var intersects = ParityTally("replay Prepared.intersects")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        let o = GEOSOracle()
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            var prepared: [Double: (PreparedGeometry, GEOSPrepared)] = [:]
            for c in r.calls {
                switch c.name {
                case "Prepared.init":
                    let p = PreparedGeometryFactory.prepare(inputs.port(c.geometries[0]))
                    prepared[c.numbers[0]] = (p, inputs.geos(c.geometries[0]).prepared())
                case "Prepared.contains", "Prepared.intersects":
                    guard let (p, gp) = prepared[c.numbers[0]] else { continue }
                    let b = inputs.port(c.geometries[0]), gb = inputs.geos(c.geometries[0])
                    let isContains = c.name == "Prepared.contains"
                    var g: Bool?
                    time.geos += clock.measure { g = gp.predicate(gb, isContains ? GEOSPreparedContains_r : GEOSPreparedIntersects_r) }
                    var m: Bool?
                    time.port += clock.measure { m = try? (isContains ? p.contains(b) : p.intersects(b)) }
                    if isContains {
                        contains.check(m == g, "\(r.name) #\(c.geometries[0]): port \(String(describing: m)) GEOS \(String(describing: g))")
                    } else {
                        intersects.check(m == g, "\(r.name) #\(c.geometries[0]): port \(String(describing: m)) GEOS \(String(describing: g))")
                    }
                default: break
                }
            }
        }
        contains.report()
        intersects.report()
        time.report("Prepared")
    }
}
}
