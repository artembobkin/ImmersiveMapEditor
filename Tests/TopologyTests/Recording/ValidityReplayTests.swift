import Foundation
import Testing
import Topology

/// The recorded `isValid` calls of `Geometry` (`GEOSisValid`) replayed on
/// the port against GEOS's stored answers: the same answer, and the same
/// reason and location of the error (`GEOSisValidDetail`), bit for bit.
@Suite(.enabled(if: Recording.stored, "no recordings or no stored answers in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct ValidityReplayTests {
    @Test func isValid() {
        var t = ValidityParityTests.Tally("replay isValid")
        var time = OverlayReplayTests.Timed()
        let clock = ContinuousClock()
        Recording.replay("ValidityReplayTests.isValid") { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == "isValid" {
                let p = inputs.port(c.geometries[0])
                var answers: (Bool?, Bool?) = (nil, o.predicate(.isValid, [inputs.input(c.geometries[0])]))
                time.port += clock.measure { answers.0 = try? p.isValid() }
                t.t.check(answers.0 == answers.1, "\(r.name) #\(c.geometries[0]): port \(String(describing: answers.0)) GEOS \(String(describing: answers.1))")
                ValidityParityTests.compare("\(r.name) #\(c.geometries[0])", p, o.validity(inputs.input(c.geometries[0])), &t)
            }
        }
        t.report()
        time.report("isValid")
    }
}
