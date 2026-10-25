import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// The core functions of a geometry against GEOS on seeded random geometries
/// (`RandomGeometries`): measures bit for bit, geometries in GEOS's normal
/// form bit for bit.
@Suite struct CoreParityTests {
    static let count = 20_000

    /// Compares a geometry the port makes with the one GEOS makes, for each
    /// random geometry.
    static func compare(_ name: String, seed: UInt64, count: Int = count, raw: Bool = false, skip: (Shape) -> Bool = { _ in false },
                        _ mine: (Topology.Geometry) -> Topology.Geometry,
                        _ geos: (GEOSGeom) -> GEOSGeom?) -> ParityTally {
        let o = GEOSOracle()
        var tally = ParityTally(name)
        var r = RandomGeometries(seed: seed)
        for _ in 0..<count {
            let s = r.geometry()
            if skip(s) { continue }
            let g = s.topology()
            let gg = o.geometry(s)!
            guard let expected = geos(gg) else {
                tally.check(false, "\(s): GEOS failed \(o.takeError() ?? "")")
                continue
            }
            let (a, b) = raw ? (Shape(mine(g)), expected.shape) : o.normalizedShapes(mine(g), expected)
            tally.check(a == b, "\(s):\n  port \(a)\n  GEOS \(b)")
        }
        return tally
    }

    static func measure(_ name: String, seed: UInt64, _ mine: (Topology.Geometry) -> Double, _ geos: (GEOSGeom) -> Double?) -> ParityTally {
        let o = GEOSOracle()
        var tally = ParityTally(name)
        var r = RandomGeometries(seed: seed)
        for _ in 0..<count {
            let s = r.geometry()
            let m = mine(s.topology()), e = geos(o.geometry(s)!)
            tally.check(m.bitPattern == e?.bitPattern, "\(s): \(m) vs \(e.map { "\($0)" } ?? "nil")")
        }
        return tally
    }

    @Test func area() { CoreParityTests.measure("area", seed: 10, { $0.getArea() }, { $0.area }).report() }
    @Test func length() { CoreParityTests.measure("length", seed: 11, { $0.getLength() }, { $0.length }).report() }

    @Test func bounds() {
        let o = GEOSOracle()
        var tally = ParityTally("bounds (envelope ordinates)")
        var r = RandomGeometries(seed: 12)
        for _ in 0..<CoreParityTests.count {
            let s = r.geometry()
            if s.isEmpty { continue }
            let e = s.topology().getEnvelopeInternal()
            let g = o.geometry(s)!
            var a = 0.0, b = 0.0, c = 0.0, d = 0.0
            GEOSGeom_getXMin_r(o.handle, g.ptr, &a)
            GEOSGeom_getYMin_r(o.handle, g.ptr, &b)
            GEOSGeom_getXMax_r(o.handle, g.ptr, &c)
            GEOSGeom_getYMax_r(o.handle, g.ptr, &d)
            tally.check([e.minX, e.minY, e.maxX, e.maxY].map(\.bitPattern) == [a, b, c, d].map(\.bitPattern), "\(s)")
        }
        tally.report()
    }

    @Test func envelope() {
        CoreParityTests.compare("envelope", seed: 13, { $0.getEnvelope() }, { $0.unary(GEOSEnvelope_r) }).report()
    }

    @Test func centroid() {
        CoreParityTests.compare("centroid", seed: 14, { $0.getCentroid() }, { $0.unary(GEOSGetCentroid_r) }).report()
    }

    @Test func interiorPoint() {
        CoreParityTests.compare("interior point", seed: 15, { $0.getInteriorPoint() }, { $0.unary(GEOSPointOnSurface_r) }).report()
    }

    @Test func convexHull() {
        CoreParityTests.compare("convex hull", seed: 16, { $0.convexHull() }, { $0.unary(GEOSConvexHull_r) }).report()
    }

    @Test func boundary() {
        // GEOS refuses the boundary of a collection, as JTS.
        CoreParityTests.compare("boundary", seed: 17, skip: { $0.kind == .geometryCollection }, { $0.getBoundary() },
                                { $0.unary(GEOSBoundary_r) }).report()
    }

    @Test func minimumRotatedRectangle() {
        CoreParityTests.compare("minimum rotated rectangle (MinimumAreaRectangle)", seed: 18, { MinimumAreaRectangle.getMinimumRectangle($0) },
                                { $0.unary(GEOSMinimumRotatedRectangle_r) }).report()
    }

    /// GEOS's minimum rotated rectangle is not JTS's `MinimumDiameter`
    /// rectangle (the one of least width): counted, not required.
    @Test func minimumDiameterIsNotGEOSs() {
        let t = CoreParityTests.compare("minimum rotated rectangle (MinimumDiameter, expected to differ)", seed: 18,
                                        { MinimumDiameter.getMinimumRectangle($0) }, { $0.unary(GEOSMinimumRotatedRectangle_r) })
        print("parity \(t.name): compared \(t.compared), equal \(t.compared - t.differences)")
        #expect(t.differences > 0)
    }

    @Test func normalize() {
        CoreParityTests.compare("normalize", seed: 19, raw: true, { $0.norm() }, { $0.normalized }).report()
    }
}
}
