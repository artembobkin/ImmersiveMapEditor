import Foundation
import Testing
import Topology

/// The recorded predicate calls of `Geometry` replayed on the port against
/// GEOS's stored answers: `intersects`, `contains`, `within`, and the
/// prepared geometries' `contains` and `intersects` (each recorded
/// `Prepared.init` prepared by the port, its later calls replayed against
/// it). Every answer equal; the port's time is printed. Long: run with
/// `TOPOLOGY_LONG_REPLAY=1`, best in a release build.
@Suite(.enabled(if: Recording.longStored, "long replays run with TOPOLOGY_LONG_REPLAY=1, the recordings and their stored answers in .build/recording"))
struct PredicateReplayTests {
    static func replay(_ name: String, _ mine: (Topology.Geometry, Topology.Geometry) throws -> Bool, _ op: PredicateOp) {
        var tally = ParityTally("replay \(name)")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        Recording.replay("PredicateReplayTests.\(name)") { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == name {
                let a = inputs.port(c.geometries[0]), b = inputs.port(c.geometries[1])
                let g = o.predicate(op, [inputs.input(c.geometries[0]), inputs.input(c.geometries[1])])
                var m: Bool?
                time.port += clock.measure { m = try? mine(a, b) }
                tally.check(m == g, "\(r.name) #\(c.geometries): port \(String(describing: m)) GEOS \(String(describing: g))")
            }
        }
        tally.report()
        time.report(name)
    }

    @Test func intersects() { PredicateReplayTests.replay("intersects", { try $0.intersects($1) }, .intersects) }
    @Test func contains() { PredicateReplayTests.replay("contains", { try $0.contains($1) }, .contains) }
    @Test func within() { PredicateReplayTests.replay("within", { try $0.within($1) }, .within) }

    @Test func prepared() {
        var contains = ParityTally("replay Prepared.contains")
        var intersects = ParityTally("replay Prepared.intersects")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        Recording.replay("PredicateReplayTests.prepared") { r, o in
            let inputs = ReplayTests.Inputs(r)
            var prepared: [Double: (PreparedGeometry, Int)] = [:]
            for c in r.calls {
                switch c.name {
                case "Prepared.init":
                    let p = PreparedGeometryFactory.prepare(inputs.port(c.geometries[0]))
                    prepared[c.numbers[0]] = (p, o.prepare(inputs.input(c.geometries[0])))
                case "Prepared.contains", "Prepared.intersects":
                    guard let (p, gp) = prepared[c.numbers[0]] else { continue }
                    let b = inputs.port(c.geometries[0])
                    let isContains = c.name == "Prepared.contains"
                    let g = o.prepared(isContains ? .contains : .intersects, gp, inputs.input(c.geometries[0]))
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
