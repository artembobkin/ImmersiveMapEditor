import Foundation
import Testing
import Topology

/// The recorded `makeValid` (`GEOSMakeValid`) and `setPrecision`
/// (`GEOSGeom_setPrecision`, flags 0) calls of `Geometry` replayed on the
/// port against GEOS's stored answers: results in GEOS's normal form bit for
/// bit, and as they come; the port's time is printed. Long (overlays): run
/// with `TOPOLOGY_LONG_REPLAY=1`.
@Suite(.enabled(if: Recording.longStored, "long replays run with TOPOLOGY_LONG_REPLAY=1, the recordings and their stored answers in .build/recording"))
struct RepairReplayTests {
    @Test func makeValid() {
        LinesReplayTests.replay("makeValid", tape: "RepairReplayTests.makeValid", { g, _ in try g[0].makeValid() }) { _ in .makeValid }
    }

    @Test func setPrecision() {
        LinesReplayTests.replay("setPrecision", tape: "RepairReplayTests.setPrecision", { g, n in try g[0].setPrecision(n[0]) }) { .setPrecision($0[0]) }
    }
}

/// The recorded `simplify` (`GEOSTopologyPreserveSimplify`),
/// `constrainedDelaunay` (`GEOSConstrainedDelaunayTriangulation`),
/// `interpolate` (`GEOSInterpolate`, `GEOSInterpolateNormalized`) and
/// `project` (`GEOSProject`) calls replayed on the port against GEOS's
/// stored answers, bit for bit.
@Suite(.enabled(if: Recording.stored, "no recordings or no stored answers in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct ShapeReplayTests {
    @Test func simplify() {
        LinesReplayTests.replay("simplify", tape: "ShapeReplayTests.simplify", { g, n in try g[0].topologyPreserveSimplify(n[0]) }) { .simplify($0[0]) }
    }

    @Test func constrainedDelaunay() {
        LinesReplayTests.replay("constrainedDelaunay", tape: "ShapeReplayTests.constrainedDelaunay",
                                { g, _ in try ConstrainedDelaunayTriangulator.triangulate(g[0]) }) { _ in .constrainedDelaunay }
    }

    @Test func interpolate() {
        LinesReplayTests.replay("interpolate", tape: "ShapeReplayTests.interpolate", { g, n in try g[0].interpolate(n[0], normalized: n[1] != 0) }) {
            .interpolate($0[0], normalized: $0[1] != 0)
        }
    }

    @Test func project() {
        var t = ParityTally("replay project")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        Recording.replay("ShapeReplayTests.project") { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == "project" {
                let p = c.geometries.map { inputs.port($0) }
                let theirs = o.project(inputs.input(c.geometries[0]), inputs.input(c.geometries[1]))
                var mine = 0.0
                time.port += clock.measure { mine = (try? p[0].project(p[1])) ?? -1 }
                t.check(mine.bitPattern == theirs.bitPattern, "\(r.name) #\(c.geometries): port \(mine) GEOS \(theirs)")
            }
        }
        t.report()
        time.report("project")
    }
}
