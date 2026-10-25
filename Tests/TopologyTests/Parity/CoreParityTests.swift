import Foundation
import Testing
import Topology

/// The core functions of a geometry against GEOS 3.13's stored answers on
/// seeded random geometries (`RandomGeometries`): measures bit for bit,
/// geometries in GEOS's normal form bit for bit.
@Suite struct CoreParityTests {
    static let count = 20_000

    /// Compares a geometry the port makes with the one GEOS made, for each
    /// random geometry. `raw`: compared as they come, not normalized.
    static func compare(_ name: String, tape: String, seed: UInt64, count: Int = count, raw: Bool = false,
                        skip: (Shape) -> Bool = { _ in false },
                        _ mine: (Topology.Geometry) -> Topology.Geometry, _ op: GeometryOp) -> ParityTally {
        let o = Oracles.make("CoreParityTests.\(tape)")
        defer { o.finish() }
        var tally = ParityTally(name)
        var r = RandomGeometries(seed: seed)
        for _ in 0..<count {
            let s = r.geometry()
            if skip(s) { continue }
            let g = s.topology()
            guard case .result(let expected) = o.geometry(op, [.shape(s)]) else {
                tally.check(false, "\(s): GEOS failed")
                continue
            }
            if raw {
                let a = Shape(mine(g))
                tally.check(expected.rawEquals(a), "\(s):\n  port \(a)\n  GEOS \(expected.description)")
            } else {
                let m = mine(g)
                tally.check(expected.compare(raw: Shape(m), normal: Shape(m.norm())) == .equal,
                            "\(s):\n  port \(Shape(m.norm()))\n  GEOS \(expected.normalDescription)")
            }
        }
        return tally
    }

    static func measure(_ name: String, tape: String, seed: UInt64, _ mine: (Topology.Geometry) -> Double, _ op: MeasureOp) -> ParityTally {
        let o = Oracles.make("CoreParityTests.\(tape)")
        defer { o.finish() }
        var tally = ParityTally(name)
        var r = RandomGeometries(seed: seed)
        for _ in 0..<count {
            let s = r.geometry()
            let m = mine(s.topology()), e = o.measure(op, [.shape(s)])
            tally.check(m.bitPattern == e?.bitPattern, "\(s): \(m) vs \(e.map { "\($0)" } ?? "nil")")
        }
        return tally
    }

    @Test func area() { CoreParityTests.measure("area", tape: "area", seed: 10, { $0.getArea() }, .area).report() }
    @Test func length() { CoreParityTests.measure("length", tape: "length", seed: 11, { $0.getLength() }, .length).report() }

    @Test func bounds() {
        let o = Oracles.make("CoreParityTests.bounds")
        defer { o.finish() }
        var tally = ParityTally("bounds (envelope ordinates)")
        var r = RandomGeometries(seed: 12)
        for _ in 0..<CoreParityTests.count {
            let s = r.geometry()
            if s.isEmpty { continue }
            let e = s.topology().getEnvelopeInternal()
            let theirs = o.bounds(.shape(s))
            tally.check(theirs.matches(TapeReader.encode([e.minX, e.minY, e.maxX, e.maxY])), "\(s)")
        }
        tally.report()
    }

    @Test func envelope() {
        CoreParityTests.compare("envelope", tape: "envelope", seed: 13, { $0.getEnvelope() }, .envelope).report()
    }

    @Test func centroid() {
        CoreParityTests.compare("centroid", tape: "centroid", seed: 14, { $0.getCentroid() }, .centroid).report()
    }

    @Test func interiorPoint() {
        CoreParityTests.compare("interior point", tape: "interiorPoint", seed: 15, { $0.getInteriorPoint() }, .pointOnSurface).report()
    }

    @Test func convexHull() {
        CoreParityTests.compare("convex hull", tape: "convexHull", seed: 16, { $0.convexHull() }, .convexHull).report()
    }

    @Test func boundary() {
        // GEOS refuses the boundary of a collection, as JTS.
        CoreParityTests.compare("boundary", tape: "boundary", seed: 17, skip: { $0.kind == .geometryCollection }, { $0.getBoundary() },
                                .boundary).report()
    }

    @Test func minimumRotatedRectangle() {
        CoreParityTests.compare("minimum rotated rectangle (MinimumAreaRectangle)", tape: "minimumRotatedRectangle", seed: 18,
                                { MinimumAreaRectangle.getMinimumRectangle($0) }, .minimumRotatedRectangle).report()
    }

    /// GEOS's minimum rotated rectangle is not JTS's `MinimumDiameter`
    /// rectangle (the one of least width): counted, not required. The same
    /// inputs as `minimumRotatedRectangle`, so the same stored answers.
    @Test func minimumDiameterIsNotGEOSs() {
        let t = CoreParityTests.compare("minimum rotated rectangle (MinimumDiameter, expected to differ)", tape: "minimumRotatedRectangle",
                                        seed: 18, { MinimumDiameter.getMinimumRectangle($0) }, .minimumRotatedRectangle)
        print("parity \(t.name): compared \(t.compared), equal \(t.compared - t.differences)")
        #expect(t.differences > 0)
    }

    @Test func normalize() {
        CoreParityTests.compare("normalize", tape: "normalize", seed: 19, raw: true, { $0.norm() }, .normalize).report()
    }
}
