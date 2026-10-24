import Foundation
import Geometry
import simd

/// Faces cut into triangles, triangles too small to draw dropped, and the
/// mesh cut to the tile's edges.

/// Triangles of a face's corners, as index triples wound as the face: a fan
/// when the face is convex, ear clipping when not.
public func triangulate(_ points: [V3]) -> [(Int, Int, Int)] {
    let n = points.count
    if n == 3 { return [(0, 1, 2)] }
    if n < 3 { return [] }
    // The face's normal (Newell) and the plane to work in.
    var nn = V3.zero
    for i in 0..<n {
        let a = points[i], b = points[(i + 1) % n]
        nn.x += (a.y - b.y) * (a.z + b.z)
        nn.y += (a.z - b.z) * (a.x + b.x)
        nn.z += (a.x - b.x) * (a.y + b.y)
    }
    let ax = [abs(nn.x), abs(nn.y), abs(nn.z)].enumerated().max { $0.element < $1.element }!.offset
    let keep = [0, 1, 2].filter { $0 != ax }
    var sign = nn[ax] >= 0 ? 1.0 : -1.0
    if ax == 1 { sign = -sign }
    let flat = points.map { P2($0[keep[0]], $0[keep[1]]) }
    func turn(_ i: Int, _ j: Int, _ k: Int) -> Double {
        let a = flat[i], b = flat[j], c = flat[k]
        return ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) * sign
    }
    if (0..<n).allSatisfy({ turn($0, ($0 + 1) % n, ($0 + 2) % n) >= -1e-12 }) {
        return (1..<(n - 1)).map { (0, $0, $0 + 1) }
    }
    func inside(_ p: P2, _ a: P2, _ b: P2, _ c: P2) -> Bool {
        func side(_ u: P2, _ v: P2, _ w: P2) -> Double { ((v.x - u.x) * (w.y - u.y) - (v.y - u.y) * (w.x - u.x)) * sign }
        return side(a, b, p) > 0 && side(b, c, p) > 0 && side(c, a, p) > 0
    }
    var left = Array(0..<n)
    var out: [(Int, Int, Int)] = []
    var guardCount = 0
    while left.count > 3 && guardCount < 4 * n * n {
        guardCount += 1
        let m = left.count
        var cut = false
        for t in 0..<m {
            let i = left[(t - 1 + m) % m], j = left[t], k = left[(t + 1) % m]
            if turn(i, j, k) <= 1e-12 { continue }
            if left.contains(where: { $0 != i && $0 != j && $0 != k && inside(flat[$0], flat[i], flat[j], flat[k]) }) {
                continue
            }
            out.append((i, j, k))
            left.remove(at: t)
            cut = true
            break
        }
        if !cut { break }
    }
    if left.count == 3 { out.append((left[0], left[1], left[2])) }
    return out
}

/// Corners on a millimetre grid, and every triangle too small to draw
/// dropped.
public func clean(_ m: Triangles) -> Triangles {
    var r = m
    r.pos = m.pos.map { ($0 * 1000).rounded() / 1000 }
    return r.filtered { t in r.normal(t).length / 2 >= 1e-5 }
}

/// The tile's edge: the faces of a neighbour's buildings removed, the
/// buildings this tile owns kept whole even where they reach over the edge,
/// and everything else clipped to the bounds. The cut faces are left open.
public func cut(_ m: Triangles, _ bounds: (Double, Double, Double, Double)) -> Triangles {
    let (x0, y0, x1, y1) = bounds
    let eps = 1e-4
    var out = Triangles()
    let planes: [(Int, Double, Double)] = [(0, x0, 1), (0, x1, -1), (1, y0, 1), (1, y1, -1)]
    for t in 0..<m.count where m.owner[t] != .foreign {
        let xs = (0..<3).map { m.pos[t * 9 + $0 * 3] }, ys = (0..<3).map { m.pos[t * 9 + $0 * 3 + 1] }
        let inner = xs.min()! >= x0 - eps && xs.max()! <= x1 + eps && ys.min()! >= y0 - eps && ys.max()! <= y1 + eps
        if m.owner[t] == .whole || inner {
            out.pos += m.pos[(t * 9)..<(t * 9 + 9)]
            out.uv += m.uv[(t * 6)..<(t * 6 + 6)]
            out.owner.append(m.owner[t])
            out.wall += m.wall[(t * 2)..<(t * 2 + 2)]
            continue
        }
        if xs.max()! <= x0 || xs.min()! >= x1 || ys.max()! <= y0 || ys.min()! >= y1 { continue }
        // Corners as (x, y, z, u, v), clipped plane by plane.
        var poly: [[Double]] = (0..<3).map { i in
            Array(m.pos[(t * 9 + i * 3)..<(t * 9 + i * 3 + 3)]) + Array(m.uv[(t * 6 + i * 2)..<(t * 6 + i * 2 + 2)])
        }
        for (axis, at, keepSide) in planes {
            var next: [[Double]] = []
            for i in 0..<poly.count {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                let da = (a[axis] - at) * keepSide, db = (b[axis] - at) * keepSide
                if da >= 0 { next.append(a) }
                if (da >= 0) != (db >= 0) {
                    let s = da / (da - db)
                    next.append(zip(a, b).map { $0 + ($1 - $0) * s })
                }
            }
            poly = next
            if poly.count < 3 { break }
        }
        guard poly.count >= 3 else { continue }
        for i in 1..<(poly.count - 1) {
            for c in [poly[0], poly[i], poly[i + 1]] {
                out.pos += c[0..<3]
                out.uv += c[3..<5]
            }
            out.owner.append(m.owner[t])
            out.wall += m.wall[(t * 2)..<(t * 2 + 2)]
        }
    }
    return clean(out)
}

