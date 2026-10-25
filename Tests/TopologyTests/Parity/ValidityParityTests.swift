import Foundation
import Testing
import Topology

/// Validity against GEOS 3.13's stored answers of `GEOSisValidDetail` (which
/// runs the same `IsValidOp` as `GEOSisValid`) on seeded random geometries
/// and on often invalid ones (`InvalidGeometries`). The answer, the reason
/// and the location of the error must all be GEOS's, the location bit for
/// bit; where GEOS failed, the port must throw.
@Suite struct ValidityParityTests {
    static func port(_ g: Topology.Geometry) throws -> Verdict {
        guard let e = try IsValidOp(g).getValidationError() else { return Verdict(valid: true, reason: "", location: []) }
        // GEOS writes a missing location as its default coordinate (0, 0),
        // and a location of NaN ordinates is its empty point, read as (0, 0).
        let c = e.coordinate.flatMap { $0.isNull ? nil : $0 } ?? Coordinate(0, 0)
        return Verdict(valid: false, reason: e.getMessage(), location: [c.x.bitPattern, c.y.bitPattern])
    }

    struct Tally {
        var t: ParityTally
        var invalid = 0
        var failingBoth = 0
        init(_ name: String) { t = ParityTally(name) }
        func report() {
            t.report()
            print("parity \(t.name): invalid \(invalid), GEOS and the port failing alike \(failingBoth)")
        }
    }

    static func compare(_ input: @autoclosure () -> String, _ mine: Topology.Geometry, _ theirs: Verdict?, _ tally: inout Tally) {
        let m = Result { try port(mine) }
        switch (m, theirs) {
        case (.failure, nil):
            tally.failingBoth += 1
            tally.t.check(true, "")
        case (.failure(let e), let g?):
            tally.t.check(false, "\(input()): the port fails (\(e)), GEOS \(g)")
        case (.success(let p), nil):
            tally.t.check(false, "\(input()): GEOS fails, the port \(p)")
        case (.success(let p), let g?):
            if !g.valid { tally.invalid += 1 }
            tally.t.check(p == g, "\(input()): port \(p) GEOS \(g)")
        }
    }

    @Test func randomGeometries() {
        let o = Oracles.make("ValidityParityTests.randomGeometries")
        defer { o.finish() }
        var t = Tally("isValid random")
        var r = RandomGeometries(seed: 600)
        for _ in 0..<6000 {
            let s = r.geometry()
            ValidityParityTests.compare("\(s)", s.topology(), o.validity(.shape(s)), &t)
        }
        t.report()
    }

    @Test func invalidGeometries() {
        let o = Oracles.make("ValidityParityTests.invalidGeometries")
        defer { o.finish() }
        var t = Tally("isValid invalid-prone")
        var r = InvalidGeometries(seed: 601)
        for _ in 0..<12000 {
            let s = r.geometry()
            ValidityParityTests.compare("\(s)", s.topology(), o.validity(.shape(s)), &t)
        }
        t.report()
    }
}
