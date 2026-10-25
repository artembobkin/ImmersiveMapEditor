import Foundation

/// A seeded generator (SplitMix64), so every random parity test is the same
/// run after run.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Random geometries for the parity tests, as shapes: valid polygons with
/// holes (star shapes around a centre), lines, points and their
/// collections, and near-degenerate ones: collinear and repeated vertices,
/// slivers, rings touching at a vertex, integer grids, coordinates far from
/// the origin.
struct RandomGeometries {
    var rng: SeededRandom

    init(seed: UInt64) { rng = SeededRandom(seed: seed) }

    mutating func double(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &rng) }
    mutating func int(_ r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &rng) }
    mutating func chance(_ p: Double) -> Bool { double(0...1) < p }

    /// An offset of the coordinates: near the origin, a city's metres, or
    /// far away (web mercator metres, degrees).
    mutating func origin() -> (Double, Double) {
        switch int(0...4) {
        case 0: return (0, 0)
        case 1: return (double(-500...500), double(-500...500))
        case 2: return (4_190_000 + double(0...1000), 7_510_000 + double(0...1000))
        case 3: return (37.6 + double(0...0.01), 55.75 + double(0...0.01))
        default: return (double(-1e7...1e7), double(-1e7...1e7))
        }
    }

    /// Rounds to a grid now and then, which makes exact collinearities.
    mutating func gridded(_ v: Double, _ grid: Double?) -> Double {
        guard let grid else { return v }
        return (v / grid).rounded() * grid
    }

    /// A star-shaped ring around `c`, closed, counter-clockwise or not.
    mutating func ring(_ c: (Double, Double), radius: ClosedRange<Double>, n: Int, grid: Double?, ccw: Bool) -> [Double] {
        var angles = (0..<n).map { _ in double(0...(2 * .pi)) }.sorted()
        if !ccw { angles.reverse() }
        var pts: [(Double, Double)] = angles.map { a in
            let r = double(radius)
            return (gridded(c.0 + r * cos(a), grid), gridded(c.1 + r * sin(a), grid))
        }
        // Near-degenerate vertices: a midpoint (collinear), a repeat, a spike.
        if pts.count > 3 && chance(0.3) {
            let i = int(0...(pts.count - 2))
            let m = ((pts[i].0 + pts[i + 1].0) / 2, (pts[i].1 + pts[i + 1].1) / 2)
            pts.insert(chance(0.5) ? m : (m.0 + double(-1e-9...1e-9), m.1), at: i + 1)
        }
        if pts.count > 3 && chance(0.2) {
            let i = int(0...(pts.count - 1))
            pts.insert(pts[i], at: i)
        }
        var out: [Double] = pts.flatMap { [$0.0, $0.1] }
        out.append(contentsOf: [pts[0].0, pts[0].1])
        return out
    }

    mutating func polygon() -> Shape {
        let o = origin()
        let scale = [1e-4, 1.0, 10.0, 300.0].randomElement(using: &rng)!
        let grid: Double? = chance(0.25) ? scale / 8 : nil
        let n = int(3...14)
        if chance(0.1) {
            // A sliver: a thin triangle or quadrilateral.
            let a = (o.0, o.1), b = (o.0 + scale, o.1 + scale * double(-1...1))
            let t = double(0.2...0.8)
            let c = (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t + scale * double(-1e-9...1e-9))
            return Shape(kind: .polygon, parts: [Shape(kind: .linearRing, coordinates: [a.0, a.1, b.0, b.1, c.0, c.1, a.0, a.1])])
        }
        let shell = ring(o, radius: (scale * 0.6)...(scale * 1.0), n: n, grid: grid, ccw: chance(0.5))
        var rings = [Shape(kind: .linearRing, coordinates: shell)]
        if chance(0.4) {
            for _ in 0..<int(1...2) {
                let hc = (o.0 + double(-0.05...0.05) * scale, o.1 + double(-0.05...0.05) * scale)
                var hole = ring(hc, radius: (scale * 0.1)...(scale * 0.3), n: int(3...8), grid: nil, ccw: chance(0.5))
                if chance(0.15) {
                    // A hole touching the shell at one of its vertices.
                    hole[0] = shell[0]; hole[1] = shell[1]
                    hole[hole.count - 2] = shell[0]; hole[hole.count - 1] = shell[1]
                }
                rings.append(Shape(kind: .linearRing, coordinates: hole))
                if rings.count > 1 && hole[0] == shell[0] { break }
            }
        }
        return Shape(kind: .polygon, parts: rings)
    }

    mutating func lineString() -> Shape {
        let o = origin()
        let scale = [1e-4, 1.0, 50.0, 1000.0].randomElement(using: &rng)!
        let grid: Double? = chance(0.25) ? scale / 16 : nil
        var pts: [Double] = []
        var p = o
        for _ in 0..<int(2...12) {
            pts.append(contentsOf: [gridded(p.0, grid), gridded(p.1, grid)])
            if chance(0.1) { pts.append(contentsOf: [gridded(p.0, grid), gridded(p.1, grid)]) }
            p = (p.0 + double(-1...1) * scale, p.1 + double(-1...1) * scale)
        }
        if chance(0.15) { pts.append(contentsOf: [pts[0], pts[1]]) }
        return Shape(kind: .lineString, coordinates: pts)
    }

    mutating func point() -> Shape {
        let o = origin()
        return Shape(kind: .point, coordinates: [o.0 + double(-100...100), o.1 + double(-100...100)])
    }

    /// Any geometry: mostly single ones, some multi-geometries and
    /// collections, now and then an empty one.
    mutating func geometry() -> Shape {
        switch int(0...19) {
        case 0...6: return polygon()
        case 7...11: return lineString()
        case 12: return point()
        case 13, 14: return Shape(kind: .multiPolygon, parts: (0..<int(1...3)).map { _ in polygon() })
        case 15: return Shape(kind: .multiLineString, parts: (0..<int(1...3)).map { _ in lineString() })
        case 16: return Shape(kind: .multiPoint, parts: (0..<int(1...6)).map { _ in point() })
        case 17: return Shape(kind: .geometryCollection, parts: [polygon(), lineString(), point()].shuffled(using: &rng))
        default:
            return [Shape(kind: .point), Shape(kind: .lineString), Shape(kind: .polygon), Shape(kind: .multiPolygon),
                    Shape(kind: .geometryCollection)].randomElement(using: &rng)!
        }
    }
}
