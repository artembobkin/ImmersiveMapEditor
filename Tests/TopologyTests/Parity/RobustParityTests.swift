import Foundation
import Testing
import Topology
import geos

/// The robust predicates against GEOS on seeded random inputs, ordinary and
/// near-degenerate: the orientation of three points (`GEOSOrientationIndex`)
/// and the intersection of two segments (`GEOSSegmentIntersection`, which is
/// GEOS's `LineIntersector`).
@Suite struct RobustParityTests {
    /// Three points, often almost collinear: the third near the line of the
    /// first two, by a few units in the last place, at every scale.
    static func triples(seed: UInt64, count: Int) -> [(Coordinate, Coordinate, Coordinate)] {
        var r = RandomGeometries(seed: seed)
        return (0..<count).map { _ in
            let o = r.origin()
            let s = [1e-6, 1.0, 1e3, 1e6].randomElement(using: &r.rng)!
            let a = Coordinate(o.0 + r.double(-1...1) * s, o.1 + r.double(-1...1) * s)
            let b = Coordinate(o.0 + r.double(-1...1) * s, o.1 + r.double(-1...1) * s)
            switch r.int(0...3) {
            case 0:
                return (a, b, Coordinate(o.0 + r.double(-1...1) * s, o.1 + r.double(-1...1) * s))
            case 1:
                let t = r.double(-2...3)
                return (a, b, Coordinate(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)))
            case 2:
                let t = r.double(-2...3)
                let c = Coordinate(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y))
                let k = Double(r.int(-4...4))
                return (a, b, Coordinate(c.x + k * c.x.ulp, c.y - k * c.y.ulp))
            default:
                // On an integer grid: exact collinearity.
                let g = { (v: Double) in v.rounded() }
                let ga = Coordinate(g(a.x), g(a.y)), gb = Coordinate(g(b.x), g(b.y))
                let t = Double(r.int(-3...3))
                return (ga, gb, Coordinate(ga.x + t * (gb.x - ga.x), ga.y + t * (gb.y - ga.y)))
            }
        }
    }

    @Test func orientationIndex() {
        let o = GEOSOracle()
        var tally = ParityTally("Orientation.index")
        for (a, b, c) in RobustParityTests.triples(seed: 1, count: 200_000) {
            let mine = Orientation.index(a, b, c)
            let geos = Int(GEOSOrientationIndex_r(o.handle, a.x, a.y, b.x, b.y, c.x, c.y))
            tally.check(mine == geos, "\(a) \(b) \(c): \(mine) vs \(geos)")
        }
        tally.report()
    }

    @Test func isCCW() {
        let o = GEOSOracle()
        var tally = ParityTally("Orientation.isCCW")
        var r = RandomGeometries(seed: 2)
        for _ in 0..<20_000 {
            let p = r.polygon()
            let ring = p.parts[0].coordinates
            let pts = stride(from: 0, to: ring.count, by: 2).map { Coordinate(ring[$0], ring[$0 + 1]) }
            let seq = GEOSCoordSeq_copyFromBuffer_r(o.handle, ring, UInt32(pts.count), 0, 0)!
            defer { GEOSCoordSeq_destroy_r(o.handle, seq) }
            var ccw: Int8 = 0
            GEOSCoordSeq_isCCW_r(o.handle, seq, &ccw)
            tally.check(Orientation.isCCW(pts) == (ccw == 1), "\(p)")
        }
        tally.report()
    }

    /// Segments that cross, touch, overlap or almost do.
    static func segmentPairs(seed: UInt64, count: Int) -> [(Coordinate, Coordinate, Coordinate, Coordinate)] {
        var r = RandomGeometries(seed: seed)
        return (0..<count).map { _ in
            let o = r.origin()
            let s = [1e-6, 1.0, 1e3, 1e6].randomElement(using: &r.rng)!
            func pt() -> Coordinate { Coordinate(o.0 + r.double(-1...1) * s, o.1 + r.double(-1...1) * s) }
            let p1 = pt(), p2 = pt()
            switch r.int(0...4) {
            case 0, 1:
                return (p1, p2, pt(), pt())
            case 2:
                // The second starts on the first, or very near it.
                let t = r.double(0...1)
                let q1 = Coordinate(p1.x + t * (p2.x - p1.x), p1.y + t * (p2.y - p1.y))
                return (p1, p2, q1, pt())
            case 3:
                // Collinear, overlapping or not.
                let t0 = r.double(-1...2), t1 = r.double(-1...2)
                return (p1, p2, Coordinate(p1.x + t0 * (p2.x - p1.x), p1.y + t0 * (p2.y - p1.y)),
                        Coordinate(p1.x + t1 * (p2.x - p1.x), p1.y + t1 * (p2.y - p1.y)))
            default:
                // Sharing an endpoint, or almost parallel.
                if r.chance(0.5) { return (p1, p2, p2, pt()) }
                let d = Coordinate((p2.x - p1.x) * 1e-9, (p2.y - p1.y) * 1e-9)
                return (p1, p2, Coordinate(p1.x + d.y, p1.y - d.x), Coordinate(p2.x - d.y, p2.y + d.x * 3))
            }
        }
    }

    @Test func segmentIntersection() {
        let o = GEOSOracle()
        var tally = ParityTally("RobustLineIntersector (GEOSSegmentIntersection)")
        for (p1, p2, q1, q2) in RobustParityTests.segmentPairs(seed: 3, count: 200_000) {
            var cx = 0.0, cy = 0.0
            let r = GEOSSegmentIntersection_r(o.handle, p1.x, p1.y, p2.x, p2.y, q1.x, q1.y, q2.x, q2.y, &cx, &cy)
            let mine = LineSegment(p1, p2).intersection(LineSegment(q1, q2))
            let equal: Bool
            if r == 1, let m = mine {
                equal = m.x.bitPattern == cx.bitPattern && m.y.bitPattern == cy.bitPattern
            } else {
                equal = (r == -1 && mine == nil)
            }
            tally.check(equal, "\(p1) \(p2) \(q1) \(q2): \(mine.map { "\($0)" } ?? "none") vs \(r == 1 ? "(\(cx), \(cy))" : "none")")
        }
        tally.report()
    }
}
