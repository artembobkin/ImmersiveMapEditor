import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// WKT written by the port as `Geometry.description` asks GEOS for it (a
/// writer with rounding precision 3, otherwise GEOS's defaults): the same
/// text.
@Suite struct WKTParityTests {
    @Test func descriptionText() {
        let o = GEOSOracle()
        var tally = ParityTally("WKT, rounding precision 3 (Geometry.description)")
        var r = RandomGeometries(seed: 40)
        let writer = GEOSWKTWriter_create_r(o.handle)
        defer { GEOSWKTWriter_destroy_r(o.handle, writer) }
        GEOSWKTWriter_setRoundingPrecision_r(o.handle, writer, 3)
        func geosText(_ g: GEOSGeom) -> String {
            let s = GEOSWKTWriter_write_r(o.handle, writer, g.ptr)!
            defer { GEOSFree_r(o.handle, s) }
            return String(cString: s)
        }
        var shapes: [Shape] = (0..<20_000).map { _ in r.geometry() }
        // Numbers at the edges of the format: halves, tiny, huge, negative zero.
        for v in [0.0005, 0.0015, 0.0025, -0.0005, 1e-9, -1e-9, 123456789.0005, 1e15, 1e16, 1.5e17, 1e21, 2.675, 1.0005, -0.0, 5e-4, 4.9999e-4, 0.1 + 0.2] {
            shapes.append(Shape(kind: .point, coordinates: [v, -v]))
        }
        for s in shapes {
            let mine = WKTWriter(roundingPrecision: 3).write(s.topology())
            let theirs = geosText(o.geometry(s)!)
            tally.check(mine == theirs, "\(s):\n  port \(mine)\n  GEOS \(theirs)")
        }
        tally.report()
    }
}
}
