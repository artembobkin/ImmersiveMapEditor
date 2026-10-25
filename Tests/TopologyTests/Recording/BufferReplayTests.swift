import Foundation
import Testing
import Topology

/// The recorded `buffer` (`GEOSBufferWithStyle`) and `offsetCurve`
/// (`GEOSOffsetCurve`) calls of `Geometry` replayed on the port against
/// GEOS's stored answers: results in GEOS's normal form bit for bit, and as
/// they come; the port's time is printed. Long: run with
/// `TOPOLOGY_LONG_REPLAY=1`.
@Suite(.enabled(if: Recording.longStored, "long replays run with TOPOLOGY_LONG_REPLAY=1, the recordings and their stored answers in .build/recording"))
struct BufferReplayTests {
    @Test func buffer() {
        var t = OverlayParityTests.Tallies("replay buffer")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        Recording.replay("BufferReplayTests.buffer") { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == "buffer" {
                let n = c.numbers
                let p = inputs.port(c.geometries[0])
                let theirs = o.geometry(.buffer(n[0], quadSegs: Int(n[1]), cap: Int(n[2]), join: Int(n[3]), mitreLimit: n[4]),
                                        [inputs.input(c.geometries[0])])
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure {
                    m = Result { try p.buffer(n[0], quadSegs: Int(n[1]), endCapStyle: Int(n[2]), joinStyle: Int(n[3]), mitreLimit: n[4]) }
                }
                OverlayParityTests.compare("\(r.name) #\(c.geometries) \(n)", { try m.get() }, theirs, &t)
            }
        }
        t.report()
        time.report("buffer")
    }

    @Test func offsetCurve() {
        var t = OverlayParityTests.Tallies("replay offsetCurve")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        Recording.replay("BufferReplayTests.offsetCurve") { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == "offsetCurve" {
                let n = c.numbers
                let p = inputs.port(c.geometries[0])
                let theirs = o.geometry(.offsetCurve(n[0], quadSegs: Int(n[1]), join: Int(n[2]), mitreLimit: n[3]), [inputs.input(c.geometries[0])])
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure {
                    m = Result { try p.offsetCurve(n[0], quadSegs: Int(n[1]), joinStyle: Int(n[2]), mitreLimit: n[3]) }
                }
                OverlayParityTests.compare("\(r.name) #\(c.geometries) \(n)", { try m.get() }, theirs, &t)
            }
        }
        t.report()
        time.report("offsetCurve")
    }
}
