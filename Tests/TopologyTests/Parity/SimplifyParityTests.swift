import Foundation
import Testing
import Topology

/// The topology-preserving simplifier against GEOS 3.13's stored answers of
/// `GEOSTopologyPreserveSimplify`, on seeded random geometries (polygons with
/// holes, lines, closed lines, collections) and often invalid ones, with
/// tolerances from a thousandth of their size to twice it, and zero.
/// Results in GEOS's normal form bit for bit, and as they come; where GEOS
/// failed, the port must throw.
@Suite struct SimplifyParityTests {
    static func tolerance(_ s: Shape, _ r: inout RandomGeometries) -> Double {
        let size = OverlayParityTests.frame(s)?.2 ?? 1
        if r.chance(0.05) { return 0 }
        return size * [0.001, 0.01, 0.05, 0.2, 0.5, 2.0].randomElement(using: &r.rng)! * r.double(0.5...1.5)
    }

    @Test(arguments: 0..<2) func randomGeometries(_ part: Int) {
        let o = Oracles.make("SimplifyParityTests.randomGeometries.\(part)")
        defer { o.finish() }
        var t = OverlayParityTests.Tallies("simplify random \(part)")
        var r = RandomGeometries(seed: 900 + UInt64(part))
        for _ in 0..<3000 {
            let s = r.geometry()
            let d = SimplifyParityTests.tolerance(s, &r)
            OverlayParityTests.compare("\(s) tolerance \(d)", { try s.topology().topologyPreserveSimplify(d) },
                                       o.geometry(.simplify(d), [.shape(s)]), &t)
        }
        t.report()
    }

    @Test func linework() {
        let o = Oracles.make("SimplifyParityTests.linework")
        defer { o.finish() }
        var t = OverlayParityTests.Tallies("simplify linework")
        var r = RandomGeometries(seed: 902)
        for _ in 0..<3000 {
            let shapes = LinesParityTests.linework(&r, o)
            let s = Shape(kind: .geometryCollection, parts: shapes)
            let d = SimplifyParityTests.tolerance(s, &r)
            OverlayParityTests.compare("\(s) tolerance \(d)", { try s.topology().topologyPreserveSimplify(d) },
                                       o.geometry(.simplify(d), [.shape(s)]), &t)
        }
        t.report()
    }

    @Test func invalidGeometries() {
        let o = Oracles.make("SimplifyParityTests.invalidGeometries")
        defer { o.finish() }
        var t = OverlayParityTests.Tallies("simplify invalid-prone")
        var r = InvalidGeometries(seed: 903)
        for _ in 0..<3000 {
            let s = r.geometry()
            let d = SimplifyParityTests.tolerance(s, &r.r)
            OverlayParityTests.compare("\(s) tolerance \(d)", { try s.topology().topologyPreserveSimplify(d) },
                                       o.geometry(.simplify(d), [.shape(s)]), &t)
        }
        t.report()
    }
}
