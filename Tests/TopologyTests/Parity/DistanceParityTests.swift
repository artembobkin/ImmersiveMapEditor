import Foundation
import Testing
import Topology
import geos

/// Distance and nearest points against GEOS 3.13 (`GEOSDistance`,
/// `GEOSNearestPoints`), on seeded random pairs that meet or lie apart, and
/// near-degenerate ones: every distance and every point bit for bit.
@Suite struct DistanceParityTests {
    /// Pairs: a random geometry and one meeting it, or apart from it.
    static func pairs(_ seed: UInt64, _ count: Int) -> [(Shape, Shape)] {
        var r = RandomGeometries(seed: seed)
        var out: [(Shape, Shape)] = []
        for _ in 0..<count {
            let a = r.geometry()
            var b = OverlayParityTests.partner(a, &r)
            if r.chance(0.5), let (_, _, size) = OverlayParityTests.frame(a) {
                // Moved away by up to twice the size.
                let dx = size * r.double(-2...2), dy = size * r.double(-2...2)
                b = OverlayParityTests.mapped(b) { ($0 + dx, $1 + dy) }
            }
            out.append((a, b))
        }
        return out
    }

    @Test func distance() {
        let o = GEOSOracle()
        var tally = ParityTally("distance (GEOSDistance)")
        for (a, b) in DistanceParityTests.pairs(600, 8000) {
            let g = o.geometry(a)!.measure(o.geometry(b)!, GEOSDistance_r)
            let m = a.topology().distance(b.topology())
            tally.check(m.bitPattern == g?.bitPattern, "\(a) distance \(b): port \(m) GEOS \(String(describing: g))")
        }
        tally.report()
    }

    @Test func nearestPoints() {
        let o = GEOSOracle()
        var tally = ParityTally("nearest points (GEOSNearestPoints)")
        for (a, b) in DistanceParityTests.pairs(610, 8000) {
            let ga = o.geometry(a)!, gb = o.geometry(b)!
            var theirs: [Double]?
            if let seq = GEOSNearestPoints_r(o.handle, ga.ptr, gb.ptr) {
                var flat = [Double](repeating: 0, count: 4)
                GEOSCoordSeq_copyToBuffer_r(o.handle, seq, &flat, 0, 0)
                GEOSCoordSeq_destroy_r(o.handle, seq)
                theirs = flat
            }
            let mine = DistanceOp.nearestPoints(a.topology(), b.topology()).map { $0.flatMap { [$0.x, $0.y] } }
            tally.check(mine?.map(\.bitPattern) == theirs?.map(\.bitPattern),
                        "\(a) nearestPoints \(b): port \(String(describing: mine)) GEOS \(String(describing: theirs))")
        }
        tally.report()
    }
}
