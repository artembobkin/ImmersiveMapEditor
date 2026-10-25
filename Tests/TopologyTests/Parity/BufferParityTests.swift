import Foundation
import Testing
import Topology
import geos

/// The buffer against GEOS 3.13's `GEOSBufferWithStyle`, on seeded random
/// geometries with distances from a thousandth of their size to three
/// times it, both signs and zero, every cap and join style, a few mitre
/// limits and segment counts. Results in GEOS's normal form, bit for bit;
/// where GEOS fails, the port must throw. The results as they come (not
/// normalized) are counted too.
@Suite struct BufferParityTests {
    struct Case: CustomStringConvertible {
        var distance: Double
        var quadSegs: Int
        var cap: Int
        var join: Int
        var mitreLimit: Double

        var description: String { "buffer \(distance) quadSegs \(quadSegs) cap \(cap) join \(join) mitre \(mitreLimit)" }
    }

    static func randomCase(_ size: Double, _ r: inout RandomGeometries) -> Case {
        let k = [0.001, 0.05, 0.3, 1.0, 3.0].randomElement(using: &r.rng)!
        var d = size > 0 ? size * k * r.double(0.5...1.5) : r.double(0.1...10)
        if r.chance(0.3) { d = -d }
        if r.chance(0.05) { d = 0 }
        return Case(distance: d,
                    quadSegs: [1, 2, 3, 4, 8, 8, 8, 16, 0, -1].randomElement(using: &r.rng)!,
                    cap: r.int(1...3), join: r.int(1...3),
                    mitreLimit: [5.0, 5.0, 1.0, 0.5, 10.0].randomElement(using: &r.rng)!)
    }

    static func geosBuffer(_ g: GEOSGeom, _ c: Case) -> GEOSGeom? {
        g.oracle.wrap(GEOSBufferWithStyle_r(g.handle, g.ptr, c.distance, Int32(c.quadSegs), Int32(c.cap), Int32(c.join), c.mitreLimit))
    }

    static func portBuffer(_ g: Topology.Geometry, _ c: Case) throws -> Topology.Geometry {
        try g.buffer(c.distance, quadSegs: c.quadSegs, endCapStyle: c.cap, joinStyle: c.join, mitreLimit: c.mitreLimit)
    }

    @Test(arguments: 0..<4) func buffer(_ part: Int) {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("buffer \(part)")
        var r = RandomGeometries(seed: 500 + UInt64(part))
        for _ in 0..<2000 {
            let s = r.geometry()
            let size = OverlayParityTests.frame(s)?.2 ?? 0
            let c = BufferParityTests.randomCase(size, &r)
            let g = o.geometry(s)!
            OverlayParityTests.compare(o, "\(s) \(c)", { try BufferParityTests.portBuffer(s.topology(), c) },
                                       BufferParityTests.geosBuffer(g, c), &t)
        }
        t.report()
    }

    /// `GEOSOffsetCurve`, on random geometries (mostly lines) with the same
    /// spread of distances and styles.
    @Test(arguments: 0..<2) func offsetCurve(_ part: Int) {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("offsetCurve \(part)")
        var r = RandomGeometries(seed: 510 + UInt64(part))
        for _ in 0..<2000 {
            let s = r.chance(0.6) ? r.lineString() : r.geometry()
            let size = OverlayParityTests.frame(s)?.2 ?? 0
            let c = BufferParityTests.randomCase(size, &r)
            let g = o.geometry(s)!
            let theirs = o.wrap(GEOSOffsetCurve_r(g.handle, g.ptr, c.distance, Int32(c.quadSegs), Int32(c.join), c.mitreLimit))
            OverlayParityTests.compare(o, "\(s) offset \(c)", {
                try s.topology().offsetCurve(c.distance, quadSegs: c.quadSegs, joinStyle: c.join, mitreLimit: c.mitreLimit)
            }, theirs, &t)
        }
        t.report()
    }
}
