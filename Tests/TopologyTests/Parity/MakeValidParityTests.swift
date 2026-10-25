import Foundation
import Testing
import Topology

/// Make valid against GEOS 3.13's stored answers of `GEOSMakeValid` (the
/// linework method), on seeded random geometries and on often invalid ones
/// (`InvalidGeometries`: bow-ties, spikes, crossing and nested holes, hole
/// cycles, overlapping multipolygons, collapsed rings and lines, non-finite
/// coordinates). Results in GEOS's normal form bit for bit, and as they
/// come; where GEOS failed, the port must throw.
@Suite struct MakeValidParityTests {
    @Test func randomGeometries() {
        let o = Oracles.make("MakeValidParityTests.randomGeometries")
        defer { o.finish() }
        var t = OverlayParityTests.Tallies("makeValid random")
        var r = RandomGeometries(seed: 1100)
        for _ in 0..<4000 {
            let s = r.geometry()
            OverlayParityTests.compare("\(s)", { try s.topology().makeValid() }, o.geometry(.makeValid, [.shape(s)]), &t)
        }
        t.report()
    }

    @Test(arguments: 0..<2) func invalidGeometries(_ part: Int) {
        let o = Oracles.make("MakeValidParityTests.invalidGeometries.\(part)")
        defer { o.finish() }
        var t = OverlayParityTests.Tallies("makeValid invalid-prone \(part)")
        var r = InvalidGeometries(seed: 1101 + UInt64(part))
        for _ in 0..<4000 {
            let s = r.geometry()
            OverlayParityTests.compare("\(s)", { try s.topology().makeValid() }, o.geometry(.makeValid, [.shape(s)]), &t)
        }
        t.report()
    }
}
