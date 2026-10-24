import Foundation
import Geometry

/// How the tile's edge treats a face: cut along it; a building this tile
/// owns, kept whole; a building a neighbour owns, there for the light map
/// only.
public enum Owner: Int8 { case cut = 0, whole = 1, foreign = 2 }

/// Triangles: corners (9 doubles each), palette UVs (6 each, V up), how the
/// tile's edge treats them, and the height their wall shades over (2 each,
/// equal when there is none).
public struct Triangles {
    public var pos: [Double] = []
    public var uv: [Double] = []
    public var owner: [Owner] = []
    public var wall: [Double] = []
    public var count: Int { owner.count }

    public init() {}

    public func corner(_ t: Int, _ i: Int) -> V3 { V3(pos[t * 9 + i * 3], pos[t * 9 + i * 3 + 1], pos[t * 9 + i * 3 + 2]) }

    public func normal(_ t: Int) -> V3 {
        let a = corner(t, 0)
        return (corner(t, 1) - a).cross(corner(t, 2) - a)
    }

    mutating func append(_ p: [V3], _ uvs: [P2], _ o: Owner, _ w: (Double, Double)) {
        for v in p { pos += [v.x, v.y, v.z] }
        for u in uvs { uv += [u.x, u.y] }
        owner.append(o)
        wall += [w.0, w.1]
    }

    func filtered(_ keep: (Int) -> Bool) -> Triangles {
        var out = Triangles()
        for t in 0..<count where keep(t) {
            out.pos += pos[(t * 9)..<(t * 9 + 9)]
            out.uv += uv[(t * 6)..<(t * 6 + 6)]
            out.owner.append(owner[t])
            out.wall += wall[(t * 2)..<(t * 2 + 2)]
        }
        return out
    }
}

/// The tile's one mesh while it is being built: triangles, each made with
/// its winding set and its palette UV (TEXCOORD_0) on each corner. Normals
/// are never recalculated, so every helper winds its faces to face outward.
/// A face of more than three corners is cut into triangles as it is made (a
/// fan if it is convex, ear clipping if not).
public final class Builder {
    public var tris = Triangles()
    /// The height a wall face shades over in the light map: the whole wall it
    /// is part of, not the face alone (see Lighting.lightUVs).
    public var span: (Double, Double)?
    /// How the tile's edge treats the faces made now.
    public var whole: Owner = .cut
    public let palette: PaletteTexture
    public var counts: [String: Int] = [:]

    public init(palette: PaletteTexture) { self.palette = palette }

    /// A face of three or more corners, wound as given. Returns how many
    /// triangles it made.
    @discardableResult
    public func face(_ points: [V3], _ uvs: [P2], _ kind: String) -> Int {
        var made = 0
        for (i, j, k) in triangulate(points) {
            let a = points[i], b = points[j], c = points[k]
            let n = (b - a).cross(c - a)
            if simd_length_squared(n) < 1e-14 { continue }
            tris.append([a, b, c], [uvs[i], uvs[j], uvs[k]], whole, span ?? (0, 0))
            made += 1
        }
        counts[kind, default: 0] += made
        return made
    }

    @discardableResult
    public func flat(_ points: [V3], _ colour: String, _ kind: String) -> Int {
        // A family with sides, seen from above.
        let name = palette.has(colour) ? colour : colour + ".lit"
        let uv = palette.uv(name)
        return face(points, Array(repeating: uv, count: points.count), kind)
    }

    /// A face coloured by the side of the sun it looks to: `family` is a wall
    /// or "roof", the palette holds its `.lit`, `.side` and `.shade`. A face
    /// looking straight up takes the lit shade.
    @discardableResult
    public func sided(_ points: [V3], _ family: String, _ kind: String) -> Int {
        let n = (points[1] - points[0]).cross(points[2] - points[0])
        let side = abs(n.z) < 0.97 * n.length ? Palette.side(n.x, n.y) : "lit"
        return flat(points, "\(family).\(side)", kind)
    }

    /// A face by `sided` if its colour has sides, plain otherwise.
    @discardableResult
    public func paint(_ points: [V3], _ colour: String, _ kind: String) -> Int {
        palette.has("\(colour).lit") ? sided(points, colour, kind) : flat(points, colour, kind)
    }

    /// A horizontal polygon with its holes, facing up (or down). With
    /// `uvOf`, each corner takes its own UV instead of the colour's cell.
    public func fill(_ poly: Geometry, _ z: Double, _ colour: String, _ kind: String, down: Bool = false,
                     uvOf: ((Double, Double) -> P2)? = nil) {
        let valid = poly.isValid ? poly : poly.buffer(0)
        for part in valid.polygons {
            for tri in part.constrainedDelaunay() where tri.count == 3 {
                var p = tri.map { v3($0, z) }
                let n = (p[1] - p[0]).cross(p[2] - p[0])
                if n.length < 1e-6 { continue }
                if (n.z < 0) != down { p = [p[0], p[2], p[1]] }
                if let uvOf {
                    face(p, p.map { uvOf($0.x, $0.y) }, kind)
                } else {
                    flat(p, colour, kind)
                }
            }
        }
    }

    /// The faces of a template (`cone`) moved by `transform`, each coloured
    /// by `colourOf(normal)`, a palette name. A face `drop` is true for is
    /// left out.
    public func instance(_ faces: [[V3]], _ transform: (V3) -> V3, _ colourOf: (V3) -> String, _ kind: String,
                         drop: (([V3]) -> Bool)? = nil) {
        for points in faces {
            let p = points.map(transform)
            if let drop, drop(p) { continue }
            let n = (p[1] - p[0]).cross(p[2] - p[0])
            if n.length < 1e-9 { continue }
            let uv = palette.uv(colourOf(n.normalized))
            face(p, Array(repeating: uv, count: p.count), kind)
        }
    }

    /// A plain wall over the edge a→b with the inside on its left, facing out.
    public func wall(_ a: P2, _ b: P2, _ z0: Double, _ z1: Double, _ colour: String, _ kind: String) {
        if z1 - z0 < 0.01 { return }
        flat([v3(a, z0), v3(b, z0), v3(b, z1), v3(a, z1)], colour, kind)
    }

    /// Plain walls round a polygon and its holes.
    public func walls(_ poly: Geometry, _ z0: Double, _ z1: Double, _ colour: String, _ kind: String,
                      skip: ((P2, P2) -> Bool)? = nil) {
        for (a, b) in edges(poly) where !(skip?(a, b) ?? false) {
            wall(a, b, z0, z1, colour, kind)
        }
    }
}

/// Every edge of a polygon and its holes, each with the polygon's inside on
/// its left.
public func edges(_ poly: Geometry) -> [(P2, P2)] {
    let p = poly.oriented(1)
    var out: [(P2, P2)] = []
    for ring in [p.exterior] + p.interiors {
        for i in 0..<max(0, ring.count - 1) {
            let a = ring[i], b = ring[i + 1]
            if simd_length_squared(a - b) > 1e-8 { out.append((a, b)) }
        }
    }
    return out
}

// MARK: Boxes for small things

/// The unit vectors along `heading` (radians) and to its left.
public func frameAxes(_ heading: Double) -> (V3, V3) {
    let u = V3(cos(heading), sin(heading), 0)
    return (u, V3(-u.y, u.x, 0))
}

/// A box from the corner `o` along the unit axes u, v, w (u × v = w), each
/// face sided by where it looks. The bottom is left out unless asked for:
/// most things stand on something.
public func block(_ b: Builder, _ o: V3, _ u: V3, _ v: V3, _ w: V3, _ lu: Double, _ lv: Double, _ lw: Double,
                  _ colour: String, _ kind: String, bottom: Bool = false, top: Bool = true) {
    func p(_ i: Double, _ j: Double, _ k: Double) -> V3 { o + u * (i * lu) + v * (j * lv) + w * (k * lw) }
    var quads: [[V3]] = [
        [p(0, 0, 0), p(1, 0, 0), p(1, 0, 1), p(0, 0, 1)],   // -v
        [p(0, 1, 0), p(0, 1, 1), p(1, 1, 1), p(1, 1, 0)],   // +v
        [p(0, 0, 0), p(0, 0, 1), p(0, 1, 1), p(0, 1, 0)],   // -u
        [p(1, 0, 0), p(1, 1, 0), p(1, 1, 1), p(1, 0, 1)],   // +u
    ]
    if top { quads.append([p(0, 0, 1), p(1, 0, 1), p(1, 1, 1), p(0, 1, 1)]) }
    if bottom { quads.append([p(0, 0, 0), p(0, 1, 0), p(1, 1, 0), p(1, 0, 0)]) }
    for q in quads { b.paint(q, colour, kind) }
}

/// A box standing on z0, centred on `centre` in plan, its length lx along
/// `heading` (radians).
public func upright(_ b: Builder, _ centre: P2, _ heading: Double, _ lx: Double, _ ly: Double, _ z0: Double,
                    _ h: Double, _ colour: String, _ kind: String, bottom: Bool = false, top: Bool = true) {
    let (u, v) = frameAxes(heading)
    let o = v3(centre, z0) - u * (lx / 2) - v * (ly / 2)
    block(b, o, u, v, V3(0, 0, 1), lx, ly, h, colour, kind, bottom: bottom, top: top)
}

/// A square bar t thick from p to q.
public func bar(_ b: Builder, _ p: V3, _ q: V3, _ t: Double, _ colour: String, _ kind: String) {
    var u = q - p
    let n = u.length
    if n < 1e-3 { return }
    u /= n
    let side = V3(0, 0, 1).cross(u)
    let v = side.length > 1e-3 ? side.normalized : V3(1, 0, 0)
    let w = u.cross(v)
    block(b, p - v * (t / 2) - w * (t / 2), u, v, w, n, t, t, colour, kind, bottom: true)
}

nonisolated(unsafe) private var cones: [String: [[V3]]] = [:]

/// The faces of a cone around +Z, centred on the origin, `radius1` at its
/// foot and `radius2` at its top (0: a point), `depth` high, each face as
/// its corners wound outward. Made once.
public func cone(segments: Int = 8, radius1: Double, radius2: Double, depth: Double, capEnds: Bool = true) -> [[V3]] {
    let key = "\(segments) \(radius1) \(radius2) \(depth) \(capEnds)"
    if let c = cones[key] { return c }
    let h = depth / 2
    let ring = (0..<segments).map { k -> P2 in
        let a = 2 * Double.pi * Double(k) / Double(segments)
        return P2(cos(a), sin(a))
    }
    let foot = ring.map { V3($0.x * radius1, $0.y * radius1, -h) }
    let top = ring.map { V3($0.x * radius2, $0.y * radius2, h) }
    var faces: [[V3]] = []
    for k in 0..<segments {
        let k2 = (k + 1) % segments
        faces.append(radius2 <= 1e-9 ? [foot[k], foot[k2], V3(0, 0, h)] : [foot[k], foot[k2], top[k2], top[k]])
    }
    if capEnds {
        faces.append(foot.reversed())
        if radius2 > 1e-9 { faces.append(top) }
    }
    cones[key] = faces
    return faces
}

// MARK: Triangles

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

import simd
