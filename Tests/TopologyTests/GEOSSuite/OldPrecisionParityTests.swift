import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// Set precision against GEOS 3.13's `GEOSGeom_setPrecision` with the flags
/// `Geometry.swift` passes (0: snap-rounded, collapsed parts removed), on
/// seeded random geometries and often invalid ones, at grids of a seventh,
/// a hundredth and a ten-thousandth of their size, 1, 0.01 and 0.001.
/// Results in GEOS's normal form bit for bit, and as they come; where GEOS
/// fails, the port must throw.
@Suite struct PrecisionParityTests {
    static func grid(_ s: Shape, _ r: inout RandomGeometries) -> Double {
        let size = OverlayParityTests.frame(s)?.2 ?? 1
        let g = [size / 7, size / 100, size / 1e4, 1.0, 0.01, 0.001].randomElement(using: &r.rng)!
        return g > 0 && g.isFinite ? g : 0.01
    }

    static func geos(_ g: GEOSGeom, _ grid: Double) -> GEOSGeom? { g.oracle.wrap(GEOSGeom_setPrecision_r(g.handle, g.ptr, grid, 0)) }

    @Test(arguments: 0..<2) func randomGeometries(_ part: Int) {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("setPrecision random \(part)")
        var r = RandomGeometries(seed: 800 + UInt64(part))
        for _ in 0..<3000 {
            let s = r.geometry()
            let grid = PrecisionParityTests.grid(s, &r)
            let g = o.geometry(s)!
            OverlayParityTests.compare(o, "\(s) grid \(grid)", { try s.topology().setPrecision(grid) }, PrecisionParityTests.geos(g, grid), &t,
                                       again: { PrecisionParityTests.geos(g, grid) })
        }
        t.report()
    }

    @Test func invalidGeometries() {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("setPrecision invalid-prone")
        var r = InvalidGeometries(seed: 802)
        for _ in 0..<4000 {
            let s = r.geometry()
            let grid = PrecisionParityTests.grid(s, &r.r)
            let g = o.geometry(s)!
            OverlayParityTests.compare(o, "\(s) grid \(grid)", { try s.topology().setPrecision(grid) }, PrecisionParityTests.geos(g, grid), &t,
                                       again: { PrecisionParityTests.geos(g, grid) })
        }
        t.report()
    }
}
}
