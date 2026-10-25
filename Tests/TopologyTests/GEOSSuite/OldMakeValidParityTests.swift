import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// Make valid against GEOS 3.13's `GEOSMakeValid` (the linework method), on
/// seeded random geometries and on often invalid ones (`InvalidGeometries`:
/// bow-ties, spikes, crossing and nested holes, hole cycles, overlapping
/// multipolygons, collapsed rings and lines, non-finite coordinates).
/// Results in GEOS's normal form bit for bit, and as they come; where GEOS
/// fails, the port must throw.
@Suite struct MakeValidParityTests {
    @Test func randomGeometries() {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("makeValid random")
        var r = RandomGeometries(seed: 1100)
        for _ in 0..<4000 {
            let s = r.geometry()
            let g = o.geometry(s)!
            OverlayParityTests.compare(o, "\(s)", { try s.topology().makeValid() }, g.unary(GEOSMakeValid_r), &t)
        }
        t.report()
    }

    @Test(arguments: 0..<2) func invalidGeometries(_ part: Int) {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("makeValid invalid-prone \(part)")
        var r = InvalidGeometries(seed: 1101 + UInt64(part))
        for _ in 0..<4000 {
            let s = r.geometry()
            let g = o.geometry(s)!
            OverlayParityTests.compare(o, "\(s)", { try s.topology().makeValid() }, g.unary(GEOSMakeValid_r), &t)
        }
        t.report()
    }
}
}
