import Foundation
import Testing
import Topology
import geos

/// The recorded `isValid` calls of `Geometry` (`GEOSisValid`) replayed on
/// the port and on GEOS: the same answer, and the same reason and location
/// of the error (`GEOSisValidDetail`), bit for bit.
@Suite(.enabled(if: Recording.available, "no recordings in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct ValidityReplayTests {
    @Test func isValid() {
        var t = ValidityParityTests.Tally("replay isValid")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        let o = GEOSOracle()
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            for c in r.calls where c.name == "isValid" {
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                var answers: (Bool?, Bool?) = (nil, nil)
                time.geos += clock.measure { answers.1 = g.predicate(GEOSisValid_r) }
                time.port += clock.measure { answers.0 = try? p.isValid() }
                t.t.check(answers.0 == answers.1, "\(r.name) #\(c.geometries[0]): port \(String(describing: answers.0)) GEOS \(String(describing: answers.1))")
                ValidityParityTests.compare(o, "\(r.name) #\(c.geometries[0])", p, g, &t)
            }
        }
        t.report()
        time.report("isValid")
    }
}
