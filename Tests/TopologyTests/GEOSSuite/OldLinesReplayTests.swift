import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// The recorded calls of `Geometry` on lines replayed on the port and on
/// GEOS: `polygonize` (`GEOSPolygonize` of the list of geometries),
/// `lineMerge` (`GEOSLineMerge`), results in GEOS's normal form bit for bit
/// and as they come; the time each side takes is printed.
@Suite(.enabled(if: Recording.available, "no recordings in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct LinesReplayTests {
    /// Replays the calls named `name`, each with its geometries.
    static func replay(_ name: String, _ mine: ([Topology.Geometry], [Double]) throws -> Topology.Geometry,
                       _ theirs: (GEOSOracle, [GEOSGeom], [Double]) -> GEOSGeom?) {
        var t = OverlayParityTests.Tallies("replay \(name)")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        let o = GEOSOracle()
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            for c in r.calls where c.name == name {
                let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
                var result: GEOSGeom?
                time.geos += clock.measure { result = theirs(o, g, c.numbers) }
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure { m = Result { try mine(p, c.numbers) } }
                OverlayParityTests.compare(o, "\(r.name) #\(c.geometries) \(c.numbers)", { try m.get() }, result, &t)
            }
        }
        t.report()
        time.report(name)
    }

    @Test func polygonize() {
        LinesReplayTests.replay("polygonize", { g, _ in try Topology.Geometry.polygonize(g) }) { o, g, _ in
            var ptrs: [OpaquePointer?] = g.map { $0.ptr }
            return o.wrap(GEOSPolygonize_r(o.handle, &ptrs, UInt32(ptrs.count)))
        }
    }

    @Test func lineMerge() {
        LinesReplayTests.replay("lineMerge", { g, _ in try g[0].lineMerge() }) { _, g, _ in g[0].unary(GEOSLineMerge_r) }
    }
}
}
