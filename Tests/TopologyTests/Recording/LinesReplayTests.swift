import Foundation
import Testing
import Topology

/// The recorded calls of `Geometry` on lines replayed on the port against
/// GEOS's stored answers: `polygonize` (`GEOSPolygonize` of the list of
/// geometries), `lineMerge` (`GEOSLineMerge`), results in GEOS's normal form
/// bit for bit and as they come; the port's time is printed.
@Suite(.enabled(if: Recording.stored, "no recordings or no stored answers in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct LinesReplayTests {
    /// Replays the calls named `name`, each with its geometries.
    static func replay(_ name: String, tape: String, _ mine: ([Topology.Geometry], [Double]) throws -> Topology.Geometry,
                       _ op: ([Double]) -> GeometryOp) {
        var t = OverlayParityTests.Tallies("replay \(name)")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        Recording.replay(tape) { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == name {
                let p = c.geometries.map { inputs.port($0) }
                let result = o.geometry(op(c.numbers), c.geometries.map { inputs.input($0) })
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure { m = Result { try mine(p, c.numbers) } }
                OverlayParityTests.compare("\(r.name) #\(c.geometries) \(c.numbers)", { try m.get() }, result, &t)
            }
        }
        t.report()
        time.report(name)
    }

    @Test func polygonize() {
        LinesReplayTests.replay("polygonize", tape: "LinesReplayTests.polygonize", { g, _ in try Topology.Geometry.polygonize(g) }) { _ in .polygonize }
    }

    @Test func lineMerge() {
        LinesReplayTests.replay("lineMerge", tape: "LinesReplayTests.lineMerge", { g, _ in try g[0].lineMerge() }) { _ in .lineMerge }
    }
}
