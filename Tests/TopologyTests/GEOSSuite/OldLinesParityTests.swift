import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// The polygonizer (`GEOSPolygonize`, as `Geometry.polygonize` calls it on a
/// list of geometries) and the line merger (`GEOSLineMerge`) against GEOS
/// 3.13, on seeded random linework: pieces of random walks on a grid (ends
/// shared exactly, some reversed, repeated, closed into loops), the noded
/// boundaries of random polygons (from GEOS's unary union, so fully noded
/// as the pipeline gives them), raw unnoded lines, dangles, cut edges and
/// nested rings. Results bit for bit, normalized and as they come; where
/// GEOS fails, the port must throw.
@Suite struct LinesParityTests {
    /// Random linework as a list of shapes (lines, multi-lines, polygons).
    static func linework(_ r: inout RandomGeometries, _ o: GEOSOracle) -> [Shape] {
        switch r.int(0...5) {
        case 0, 1:
            // Pieces of random walks on a grid: shared ends, loops, repeats.
            let s = [1.0, 0.5, 10.0, 1e-3].randomElement(using: &r.rng)!
            let ox = r.chance(0.5) ? 0 : (r.origin().0).rounded(), oy = r.chance(0.5) ? 0 : (r.origin().1).rounded()
            var lines: [Shape] = []
            for _ in 0..<r.int(1...4) {
                var p = (r.int(0...5), r.int(0...5))
                var walk = [p]
                for _ in 0..<r.int(2...14) {
                    switch r.int(0...3) {
                    case 0: p.0 += 1
                    case 1: p.0 -= 1
                    case 2: p.1 += 1
                    default: p.1 -= 1
                    }
                    if r.chance(0.15) { p = (p.0 + r.int(-1...1), p.1 + r.int(-1...1)) }
                    walk.append(p)
                }
                if r.chance(0.3) { walk.append(walk[0]) }
                // Cut the walk into pieces at random vertices.
                var start = 0
                while start < walk.count - 1 {
                    let end = min(walk.count - 1, start + r.int(1...4))
                    var piece = Array(walk[start...end])
                    if r.chance(0.4) { piece.reverse() }
                    let c = piece.flatMap { [ox + Double($0.0) * s, oy + Double($0.1) * s] }
                    lines.append(Shape(kind: .lineString, coordinates: c))
                    if r.chance(0.05) { lines.append(Shape(kind: .lineString, coordinates: c)) }
                    start = end
                }
            }
            if r.chance(0.3) { lines = [Shape(kind: .multiLineString, parts: lines)] }
            return lines.shuffled(using: &r.rng)
        case 2, 3:
            // The noded boundaries of random geometries, as GEOS's union gives them.
            var parts: [Shape] = []
            for _ in 0..<r.int(1...3) {
                let a = r.geometry()
                parts.append(a)
                if r.chance(0.5) { parts.append(OverlayParityTests.partner(a, &r)) }
            }
            var lines: [OpaquePointer?] = []
            for p in parts {
                guard let g = o.geometry(p), let b = g.unary(GEOSBoundary_r) else { _ = o.takeError(); continue }
                lines.append(GEOSGeom_clone_r(o.handle, b.ptr))
                _ = g
            }
            guard !lines.isEmpty, let c = o.wrap(GEOSGeom_createCollection_r(o.handle, 7, &lines, UInt32(lines.count))),
                  let u = c.unaryUnion else { _ = o.takeError(); return [r.lineString()] }
            if r.chance(0.5) { return [u.shape] }
            return (0..<u.numGeometries).map { u.geometry($0).shape }
        case 4:
            // Polygons themselves (their rings are the linework), touching or nested.
            return (0..<r.int(1...3)).map { _ in r.polygon() }
        default:
            // Raw random lines, crossing without nodes.
            return (0..<r.int(1...5)).map { _ in r.lineString() }
        }
    }

    @Test func polygonize() {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("polygonize")
        var nonEmpty = 0
        var r = RandomGeometries(seed: 700)
        for _ in 0..<4000 {
            let shapes = LinesParityTests.linework(&r, o)
            let gs = shapes.map { o.geometry($0)! }
            var ptrs: [OpaquePointer?] = gs.map { $0.ptr }
            // The geometries must outlive the call (an optimized build frees them
            // after their last use, the pointers taken).
            let theirs = withExtendedLifetime(gs) { o.wrap(GEOSPolygonize_r(o.handle, &ptrs, UInt32(ptrs.count))) }
            if let theirs, theirs.numGeometries > 0 { nonEmpty += 1 }
            OverlayParityTests.compare(o, "\(shapes)", { try Topology.Geometry.polygonize(shapes.map { $0.topology() }) }, theirs, &t)
        }
        t.report()
        print("parity polygonize: \(nonEmpty) results with polygons")
    }

    @Test func lineMerge() {
        let o = GEOSOracle()
        var t = OverlayParityTests.Tallies("lineMerge")
        var merged = 0
        var r = RandomGeometries(seed: 701)
        for _ in 0..<4000 {
            let shapes = LinesParityTests.linework(&r, o)
            let s = shapes.count == 1 ? shapes[0] : Shape(kind: .geometryCollection, parts: shapes)
            let g = o.geometry(s)!
            let theirs = g.unary(GEOSLineMerge_r)
            if let theirs, theirs.numGeometries < LinesParityTests.lineCount(s) { merged += 1 }
            OverlayParityTests.compare(o, "\(s)", { try s.topology().lineMerge() }, theirs, &t)
        }
        t.report()
        print("parity lineMerge: \(merged) inputs with lines merged")
    }

    /// The number of line strings (and rings) in a shape.
    static func lineCount(_ s: Shape) -> Int {
        switch s.kind {
        case .lineString, .linearRing: return 1
        case .polygon: return s.parts.count
        default: return s.parts.reduce(0) { $0 + lineCount($1) }
        }
    }
}
}
