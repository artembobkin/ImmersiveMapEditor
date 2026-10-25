import Foundation
import Testing
import Topology
import geos

/// The constrained Delaunay triangulation of polygons against GEOS 3.13's
/// `GEOSConstrainedDelaunayTriangulation`, on seeded random polygons with
/// holes (some touching the shell), multipolygons, grids (many cocircular
/// points, collinear vertices) and the often invalid geometries; and the
/// linear referencing (`GEOSInterpolate`, `GEOSInterpolateNormalized`,
/// `GEOSProject`) on random lines and multi-lines, with distances inside,
/// outside and negative. Results bit for bit (triangles as they come);
/// where GEOS fails, the port must throw.
@Suite struct TriangulationParityTests {
    /// A polygon on a grid: a rectangle of grid points, often with a
    /// rectangular hole, so many vertices are cocircular and collinear.
    static func gridPolygon(_ r: inout RandomGeometries) -> Shape {
        let s = [1.0, 0.5, 10.0].randomElement(using: &r.rng)!
        let w = r.int(2...8), h = r.int(2...8)
        var shell: [(Double, Double)] = []
        for i in 0...w { shell.append((Double(i), 0)) }
        for j in 1...h { shell.append((Double(w), Double(j))) }
        for i in stride(from: w - 1, through: 0, by: -1) { shell.append((Double(i), Double(h))) }
        for j in stride(from: h - 1, through: 1, by: -1) { shell.append((0, Double(j))) }
        var rings = [shell.map { ($0.0 * s, $0.1 * s) }]
        if w > 2 && h > 2 && r.chance(0.6) {
            let x0 = Double(r.int(1...(w - 2))), y0 = Double(r.int(1...(h - 2)))
            let x1 = Double(r.int(Int(x0) + 1...(w - 1))), y1 = Double(r.int(Int(y0) + 1...(h - 1)))
            rings.append([(x0, y0), (x0, y1), (x1, y1), (x1, y0)].map { ($0.0 * s, $0.1 * s) })
        }
        return InvalidGeometries.polygon(rings)
    }

    /// Compares one triangulation. GEOS's triangulator requires valid
    /// polygons and crashes on some invalid ones (a hole crossing its shell:
    /// a segmentation fault), so an invalid input is not given to it and is
    /// counted apart in `skipped`.
    static func compareTriangulation(_ o: GEOSOracle, _ s: Shape, _ t: inout OverlayParityTests.Tallies, _ skipped: inout Int) {
        let g = o.geometry(s)!
        guard g.predicate(GEOSisValid_r) == true else {
            _ = o.takeError()
            skipped += 1
            return
        }
        OverlayParityTests.compare(o, "\(s)", { try ConstrainedDelaunayTriangulator.triangulate(s.topology()) },
                                   g.unary(GEOSConstrainedDelaunayTriangulation_r), &t)
    }

    @Test func randomPolygons() {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("constrainedDelaunay random")
        var skipped = 0
        defer { print("parity constrainedDelaunay random: \(skipped) invalid inputs not given to GEOS") }
        var r = RandomGeometries(seed: 1000)
        for i in 0..<4000 {
            let s: Shape
            switch i % 4 {
            case 0: s = TriangulationParityTests.gridPolygon(&r)
            case 1: s = Shape(kind: .multiPolygon, parts: (0..<r.int(1...3)).map { _ in r.polygon() })
            default: s = r.polygon()
            }
            TriangulationParityTests.compareTriangulation(o, s, &t, &skipped)
        }
        t.report()
    }

    @Test func invalidGeometries() {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("constrainedDelaunay invalid-prone")
        var skipped = 0
        defer { print("parity constrainedDelaunay invalid-prone: \(skipped) invalid inputs not given to GEOS") }
        var r = InvalidGeometries(seed: 1001)
        for _ in 0..<3000 { TriangulationParityTests.compareTriangulation(o, r.geometry(), &t, &skipped) }
        t.report()
    }

    /// GEOS's interpolated point, or nil when GEOS fails.
    static func geosInterpolate(_ g: GEOSGeom, _ d: Double, _ normalized: Bool) -> GEOSGeom? {
        g.oracle.wrap(normalized ? GEOSInterpolateNormalized_r(g.handle, g.ptr, d) : GEOSInterpolate_r(g.handle, g.ptr, d))
    }

    @Test func linearReferencing() {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("interpolate")
        var p = ParityTally("project")
        var r = RandomGeometries(seed: 1002)
        for _ in 0..<6000 {
            let s: Shape = r.chance(0.7) ? r.lineString() : Shape(kind: .multiLineString, parts: (0..<r.int(1...3)).map { _ in r.lineString() })
            let g = o.geometry(s)!
            let len = g.length ?? 1
            let normalized = r.chance(0.3)
            var d = normalized ? r.double(-1.2...1.2) : len * r.double(-1.2...1.2)
            if r.chance(0.1) { d = [0, len, -len, 0.5 * len].randomElement(using: &r.rng)! }
            OverlayParityTests.compare(o, "\(s) interpolate \(d) \(normalized)", { try s.topology().interpolate(d, normalized: normalized) },
                                       TriangulationParityTests.geosInterpolate(g, d, normalized), &t)
            // A point near the line, or one of its vertices.
            let first = s.coordinates.isEmpty ? (s.parts.first?.coordinates ?? []) : s.coordinates
            let x0 = first.first ?? 0, y0 = first.count > 1 ? first[1] : 0
            let q = r.chance(0.3) ? Shape(kind: .point, coordinates: [x0, y0])
                : Shape(kind: .point, coordinates: [x0 + r.double(-1...1) * len, y0 + r.double(-1...1) * len])
            let gq = o.geometry(q)!
            let theirs = GEOSProject_r(o.handle, g.ptr, gq.ptr)
            let mine = (try? s.topology().project(q.topology())) ?? -1
            p.check(mine.bitPattern == theirs.bitPattern, "\(s) project \(q): port \(mine) GEOS \(theirs)")
        }
        t.report()
        p.report()
    }
}
