import Foundation
import Testing
import Topology
import geos

/// The recorded `buffer` (`GEOSBufferWithStyle`) and `offsetCurve`
/// (`GEOSOffsetCurve`) calls of `Geometry` replayed on the port and on
/// GEOS: results in GEOS's normal form bit for bit, and as they come; the
/// time each side takes is printed. Long: run with `TOPOLOGY_LONG_REPLAY=1`.
@Suite(.enabled(if: Recording.longReplay, "long replays run with TOPOLOGY_LONG_REPLAY=1 and the recordings in .build/recording"))
struct BufferReplayTests {
    @Test func buffer() {
        var t = OverlayParityTests.Tallies("replay buffer")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        let o = GEOSOracle()
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            for c in r.calls where c.name == "buffer" {
                let n = c.numbers
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                var theirs: GEOSGeom?
                time.geos += clock.measure {
                    theirs = o.wrap(GEOSBufferWithStyle_r(g.handle, g.ptr, n[0], Int32(n[1]), Int32(n[2]), Int32(n[3]), n[4]))
                }
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure {
                    m = Result { try p.buffer(n[0], quadSegs: Int(n[1]), endCapStyle: Int(n[2]), joinStyle: Int(n[3]), mitreLimit: n[4]) }
                }
                OverlayParityTests.compare(o, "\(r.name) #\(c.geometries) \(n)", { try m.get() }, theirs, &t)
            }
        }
        t.report()
        time.report("buffer")
    }

    @Test func offsetCurve() {
        var t = OverlayParityTests.Tallies("replay offsetCurve")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        let o = GEOSOracle()
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            for c in r.calls where c.name == "offsetCurve" {
                let n = c.numbers
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                var theirs: GEOSGeom?
                time.geos += clock.measure { theirs = o.wrap(GEOSOffsetCurve_r(g.handle, g.ptr, n[0], Int32(n[1]), Int32(n[2]), n[3])) }
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure {
                    m = Result { try p.offsetCurve(n[0], quadSegs: Int(n[1]), joinStyle: Int(n[2]), mitreLimit: n[3]) }
                }
                OverlayParityTests.compare(o, "\(r.name) #\(c.geometries) \(n)", { try m.get() }, theirs, &t)
            }
        }
        t.report()
        time.report("offsetCurve")
    }
}
