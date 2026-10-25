import Foundation

/// Random geometries that are often invalid, for the parity of validity,
/// make valid and precision: rings whose vertices are shuffled (crossing
/// themselves), bow-ties and figure eights, spikes and gores, holes crossing
/// or outside their shell, nested and duplicated holes, holes touching each
/// other and the shell in a cycle, overlapping and nested polygons of a
/// multipolygon, rings and lines of too few distinct points, and non-finite
/// coordinates. Many coordinates are on an integer grid, so touches are exact.
struct InvalidGeometries {
    var r: RandomGeometries

    init(seed: UInt64) { r = RandomGeometries(seed: seed) }

    /// A closed ring of the points.
    static func ring(_ pts: [(Double, Double)]) -> Shape {
        var c = pts.flatMap { [$0.0, $0.1] }
        if let f = pts.first { c.append(contentsOf: [f.0, f.1]) }
        return Shape(kind: .linearRing, coordinates: c)
    }

    static func polygon(_ rings: [[(Double, Double)]]) -> Shape { Shape(kind: .polygon, parts: rings.map(ring)) }

    mutating func frame() -> (ox: Double, oy: Double, s: Double) {
        let o: (Double, Double) = r.chance(0.5) ? (0, 0) : r.origin()
        let s = [1.0, 10.0, 100.0, 1e-3].randomElement(using: &r.rng)!
        return (o.0.rounded(), o.1.rounded(), s)
    }

    /// A random point of the grid of `n` cells of size `s` (or off it).
    mutating func gridPoint(_ f: (ox: Double, oy: Double, s: Double), _ n: Int) -> (Double, Double) {
        let x = Double(r.int(0...n)), y = Double(r.int(0...n))
        if r.chance(0.2) { return (f.ox + (x + r.double(0...1)) * f.s, f.oy + (y + r.double(0...1)) * f.s) }
        return (f.ox + x * f.s, f.oy + y * f.s)
    }

    /// A box of the grid.
    func box(_ f: (ox: Double, oy: Double, s: Double), _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, ccw: Bool = true) -> [(Double, Double)] {
        let pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)].map { (f.ox + $0.0 * f.s, f.oy + $0.1 * f.s) }
        return ccw ? pts : pts.reversed()
    }

    mutating func geometry() -> Shape {
        let f = frame()
        switch r.int(0...17) {
        case 0:
            // A ring of random grid points in random order: crossing itself.
            let n = r.int(3...9)
            return InvalidGeometries.polygon([(0..<n).map { _ in gridPoint(f, 6) }])
        case 1:
            // A bow-tie, or a figure eight touching itself at a vertex.
            if r.chance(0.5) { return InvalidGeometries.polygon([[(0.0, 0.0), (4, 4), (4, 0), (0, 4)].map { (f.ox + $0.0 * f.s, f.oy + $0.1 * f.s) }]) }
            let pts = [(0.0, 0.0), (2, 2), (4, 0), (4, 4), (2, 2), (0, 4)].map { (f.ox + $0.0 * f.s, f.oy + $0.1 * f.s) }
            return InvalidGeometries.polygon([pts])
        case 2:
            // A spike or a gore: a vertex going out and back along one line.
            var pts = box(f, 0, 0, 4, 4)
            let spike = r.chance(0.5) ? (f.ox + 6 * f.s, f.oy + 2 * f.s) : (f.ox + 2 * f.s, f.oy + 2 * f.s)
            pts.insert(contentsOf: [(f.ox + 4 * f.s, f.oy + 2 * f.s), spike, (f.ox + 4 * f.s, f.oy + 2 * f.s)], at: 2)
            return InvalidGeometries.polygon([pts])
        case 3:
            // A hole somewhere: inside, crossing, touching or outside the shell.
            let a = Double(r.int(-2...5)), b = Double(r.int(-2...5))
            return InvalidGeometries.polygon([box(f, 0, 0, 6, 6), box(f, a, b, a + Double(r.int(1...4)), b + Double(r.int(1...4)), ccw: false)])
        case 4:
            // Nested holes, or the same hole twice.
            let inner = r.chance(0.5) ? box(f, 2, 2, 3, 3, ccw: false) : box(f, 1, 1, 5, 5, ccw: false)
            return InvalidGeometries.polygon([box(f, 0, 0, 6, 6), box(f, 1, 1, 5, 5, ccw: false), inner])
        case 5:
            // Holes touching each other and the shell: a cycle disconnects the interior.
            let holes: [[(Double, Double)]] = [
                [(0, 3), (3, 1), (3, 5)].map { (f.ox + $0.0 * f.s, f.oy + $0.1 * f.s) },
                [(3, 1), (6, 3), (3, 5)].map { (f.ox + $0.0 * f.s, f.oy + $0.1 * f.s) },
            ]
            return InvalidGeometries.polygon([box(f, 0, 0, 6, 6)] + holes.prefix(r.int(1...2)))
        case 6:
            // A hole touching the shell twice (a disconnected interior).
            return InvalidGeometries.polygon([box(f, 0, 0, 6, 6), [(0.0, 3.0), (3, 1), (6, 3), (3, 5)].map { (f.ox + $0.0 * f.s, f.oy + $0.1 * f.s) }])
        case 7, 8:
            // Polygons of a multipolygon: overlapping, touching along an edge, at a point, nested, apart.
            let n = r.int(2...4)
            let polys = (0..<n).map { _ -> Shape in
                let a = Double(r.int(0...6)), b = Double(r.int(0...6))
                let w = Double(r.int(1...4)), h = Double(r.int(1...4))
                var rings = [box(f, a, b, a + w, b + h)]
                if r.chance(0.3) && w > 2 && h > 2 { rings.append(box(f, a + 1, b + 1, a + w - 1, b + h - 1, ccw: false)) }
                return InvalidGeometries.polygon(rings)
            }
            return Shape(kind: .multiPolygon, parts: polys)
        case 9:
            // Rings and lines with too few distinct points, rings not closed.
            let p = gridPoint(f, 4), q = gridPoint(f, 4)
            switch r.int(0...3) {
            case 0: return Shape(kind: .polygon, parts: [Shape(kind: .linearRing, coordinates: [p.0, p.1, q.0, q.1, q.0, q.1, p.0, p.1])])
            case 1: return Shape(kind: .lineString, coordinates: [p.0, p.1, p.0, p.1])
            case 2: return Shape(kind: .multiLineString, parts: [Shape(kind: .lineString, coordinates: [p.0, p.1, q.0, q.1]), Shape(kind: .lineString, coordinates: [q.0, q.1, q.0, q.1])])
            default: return Shape(kind: .polygon, parts: [Shape(kind: .linearRing, coordinates: [p.0, p.1, q.0, q.1, p.0, q.1, p.0, p.1]), Shape(kind: .linearRing, coordinates: [p.0, p.1, p.0, p.1, p.0, p.1, p.0, p.1])])
            }
        case 10:
            // A non-finite coordinate.
            var s = r.geometry()
            func poison(_ t: inout Shape) {
                // A ring keeps its first and last points, so it stays closed.
                let isRing = t.kind == .linearRing && t.coordinates.count >= 8
                let range = isRing ? 2...(t.coordinates.count - 3) : 0...max(0, t.coordinates.count - 1)
                if !t.coordinates.isEmpty { t.coordinates[r.int(range)] = [Double.nan, .infinity, -.infinity].randomElement(using: &r.rng)! }
                else if !t.parts.isEmpty { poison(&t.parts[r.int(0...(t.parts.count - 1))]) }
            }
            poison(&s)
            return s
        case 11:
            // A polygon touching itself at a vertex from inside (an inverted ring).
            let pts = [(0.0, 0.0), (6, 0), (6, 6), (3, 6), (4, 3), (2, 3), (3, 6), (0, 6)].map { (f.ox + $0.0 * f.s, f.oy + $0.1 * f.s) }
            return InvalidGeometries.polygon([pts])
        case 12:
            // A shell and a hole with a collinear overlap of edges.
            return InvalidGeometries.polygon([box(f, 0, 0, 6, 6), box(f, 0, 1, 2, 3, ccw: false)])
        case 13:
            // A collection of random geometries, invalid ones among them.
            return Shape(kind: .geometryCollection, parts: (0..<r.int(1...3)).map { _ in r.chance(0.5) ? r.geometry() : simple() })
        case 14:
            // A random valid polygon with its vertices shuffled a little.
            var s = r.polygon()
            if var c = s.parts.first?.coordinates, c.count >= 8 {
                let n = c.count / 2 - 1
                let i = r.int(0...(n - 1)), j = r.int(0...(n - 1))
                c.swapAt(2 * i, 2 * j); c.swapAt(2 * i + 1, 2 * j + 1)
                c[2 * n] = c[0]; c[2 * n + 1] = c[1]
                s.parts[0].coordinates = c
            }
            return s
        case 15:
            // A multipolygon of random polygons near each other.
            let a = r.polygon()
            return Shape(kind: .multiPolygon, parts: [a, OverlayParityTests.partner(a, &r)].filter { $0.kind == .polygon })
        case 16:
            // A linear ring of random points (valid when simple).
            let n = r.int(3...7)
            return InvalidGeometries.ring((0..<n).map { _ in gridPoint(f, 5) })
        default:
            return r.geometry()
        }
    }

    /// One of the simpler invalid shapes.
    mutating func simple() -> Shape {
        let f = frame()
        return InvalidGeometries.polygon([(0..<r.int(3...7)).map { _ in gridPoint(f, 5) }])
    }
}
