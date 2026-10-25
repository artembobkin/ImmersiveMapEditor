import Foundation
import Testing
import Topology
import geos

/// The recorded `makeValid` (`GEOSMakeValid`) and `setPrecision`
/// (`GEOSGeom_setPrecision`, flags 0) calls of `Geometry` replayed on the
/// port and on GEOS: results in GEOS's normal form bit for bit, and as they
/// come; the time each side takes is printed. Long (overlays): run with
/// `TOPOLOGY_LONG_REPLAY=1`.
@Suite(.enabled(if: Recording.longReplay, "long replays run with TOPOLOGY_LONG_REPLAY=1 and the recordings in .build/recording"))
struct RepairReplayTests {
    @Test func makeValid() {
        LinesReplayTests.replay("makeValid", { g, _ in try g[0].makeValid() }) { _, g, _ in g[0].unary(GEOSMakeValid_r) }
    }

    @Test func setPrecision() {
        LinesReplayTests.replay("setPrecision", { g, n in try g[0].setPrecision(n[0]) }) { o, g, n in
            o.wrap(GEOSGeom_setPrecision_r(o.handle, g[0].ptr, n[0], 0))
        }
    }
}

/// The recorded `simplify` (`GEOSTopologyPreserveSimplify`),
/// `constrainedDelaunay` (`GEOSConstrainedDelaunayTriangulation`),
/// `interpolate` (`GEOSInterpolate`, `GEOSInterpolateNormalized`) and
/// `project` (`GEOSProject`) calls replayed on both sides, bit for bit.
@Suite(.enabled(if: Recording.available, "no recordings in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct ShapeReplayTests {
    @Test func simplify() {
        LinesReplayTests.replay("simplify", { g, n in try g[0].topologyPreserveSimplify(n[0]) }) { _, g, n in
            g[0].unary(GEOSTopologyPreserveSimplify_r, n[0])
        }
    }

    @Test func constrainedDelaunay() {
        LinesReplayTests.replay("constrainedDelaunay", { g, _ in try ConstrainedDelaunayTriangulator.triangulate(g[0]) }) { _, g, _ in
            g[0].unary(GEOSConstrainedDelaunayTriangulation_r)
        }
    }

    @Test func interpolate() {
        LinesReplayTests.replay("interpolate", { g, n in try g[0].interpolate(n[0], normalized: n[1] != 0) }) { _, g, n in
            TriangulationParityTests.geosInterpolate(g[0], n[0], n[1] != 0)
        }
    }

    @Test func project() {
        var t = ParityTally("replay project")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        let o = GEOSOracle()
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            for c in r.calls where c.name == "project" {
                let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
                var theirs = 0.0, mine = 0.0
                time.geos += clock.measure { theirs = GEOSProject_r(o.handle, g[0].ptr, g[1].ptr) }
                time.port += clock.measure { mine = (try? p[0].project(p[1])) ?? -1 }
                t.check(mine.bitPattern == theirs.bitPattern, "\(r.name) #\(c.geometries): port \(mine) GEOS \(theirs)")
            }
        }
        t.report()
        time.report("project")
    }
}
