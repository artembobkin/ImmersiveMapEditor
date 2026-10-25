import Foundation
import Testing
import Topology

/// The polygonizer (`GEOSPolygonize`, as `Geometry.polygonize` calls it on a
/// list of geometries) and the line merger (`GEOSLineMerge`) against GEOS
/// 3.13's stored answers, on seeded random linework: pieces of random walks
/// on a grid (ends shared exactly, some reversed, repeated, closed into
/// loops), the noded boundaries of random polygons (a unary union, so fully
/// noded as the pipeline gives them), raw unnoded lines, dangles, cut edges
/// and nested rings. Results bit for bit, normalized and as they come; where
/// GEOS failed, the port must throw.
@Suite struct LinesParityTests {
    /// Random linework as a list of shapes (lines, multi-lines, polygons).
    /// The noded boundaries were GEOS's (`GEOSBoundary`, `GEOSUnaryUnion`):
    /// they are made with the port, and the oracle checks them against GEOS's.
    static func linework(_ r: inout RandomGeometries, _ o: StoredOracle) -> [Shape] {
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
            // The noded boundaries of random geometries, as a union gives them.
            var parts: [Shape] = []
            for _ in 0..<r.int(1...3) {
                let a = r.geometry()
                parts.append(a)
                if r.chance(0.5) { parts.append(OverlayParityTests.partner(a, &r)) }
            }
            // GEOS refuses the boundary of a geometry collection: such a part is left out.
            let lines = parts.map { $0.topology() }.filter { type(of: $0) != GeometryCollection.self }.map { $0.getBoundary() }
            let union = lines.isEmpty ? nil : try? GeometryFactory.default.createGeometryCollection(lines).union()
            o.linework(parts, made: union.map(Shape.init))
            guard let u = union else { return [r.lineString()] }
            if r.chance(0.5) { return [Shape(u)] }
            return (0..<u.getNumGeometries()).map { Shape(u.getGeometryN($0)) }
        case 4:
            // Polygons themselves (their rings are the linework), touching or nested.
            return (0..<r.int(1...3)).map { _ in r.polygon() }
        default:
            // Raw random lines, crossing without nodes.
            return (0..<r.int(1...5)).map { _ in r.lineString() }
        }
    }

    @Test func polygonize() {
        let o = Oracles.make("LinesParityTests.polygonize")
        defer { o.finish() }
        var t = OverlayParityTests.Tallies("polygonize")
        var nonEmpty = 0
        var r = RandomGeometries(seed: 700)
        for _ in 0..<4000 {
            let shapes = LinesParityTests.linework(&r, o)
            let theirs = o.geometry(.polygonize, shapes.map { .shape($0) })
            if let g = theirs.result, g.numGeometries > 0 { nonEmpty += 1 }
            OverlayParityTests.compare("\(shapes)", { try Topology.Geometry.polygonize(shapes.map { $0.topology() }) }, theirs, &t)
        }
        t.report()
        print("parity polygonize: \(nonEmpty) results with polygons")
    }

    @Test func lineMerge() {
        let o = Oracles.make("LinesParityTests.lineMerge")
        defer { o.finish() }
        var t = OverlayParityTests.Tallies("lineMerge")
        var merged = 0
        var r = RandomGeometries(seed: 701)
        for _ in 0..<4000 {
            let shapes = LinesParityTests.linework(&r, o)
            let s = shapes.count == 1 ? shapes[0] : Shape(kind: .geometryCollection, parts: shapes)
            let theirs = o.geometry(.lineMerge, [.shape(s)])
            if let g = theirs.result, g.numGeometries < LinesParityTests.lineCount(s) { merged += 1 }
            OverlayParityTests.compare("\(s)", { try s.topology().lineMerge() }, theirs, &t)
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
