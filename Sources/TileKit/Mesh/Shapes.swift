import Foundation
import Geometry

/// Small things made of boxes and bars, and cones made once.

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
