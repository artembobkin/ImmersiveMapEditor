import Foundation
import simd

/// A point in local metres: X east, Y north from the range's Mercator centre.
typealias Vec2 = SIMD2<Double>

extension Vec2 {
    var length: Double { simd_length(self) }
    var normalized: Vec2 { let l = length; return l > 1e-12 ? self / l : .zero }
    /// The vector turned a quarter to the left.
    var left: Vec2 { Vec2(-y, x) }
    static func fromAngle(_ degrees: Double) -> Vec2 {
        let r = degrees * .pi / 180
        return Vec2(cos(r), sin(r))
    }
    var angle: Double { atan2(y, x) * 180 / .pi }
    func rotated(_ degrees: Double, around c: Vec2 = .zero) -> Vec2 {
        let r = degrees * .pi / 180
        let d = self - c
        return c + Vec2(d.x * cos(r) - d.y * sin(r), d.x * sin(r) + d.y * cos(r))
    }
}

func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }

/// Web Mercator around the centre of a range of tiles, at the Mercator scale
/// of that latitude: the projection of `Region` in build/common.py.
struct Projection {
    static let extent = 4096.0
    static let earthCircumference = 40075016.686
    let z: Int
    let gx: Double, gy: Double
    let unitsPerMetre: Double

    init(z: Int, x0: Int, y0: Int, x1: Int, y1: Int) {
        self.z = z
        gx = Double(x0 + x1 + 1) / 2 * Projection.extent
        gy = Double(y0 + y1 + 1) / 2 * Projection.extent
        let row = Double(y0 + y1 + 1) / 2
        let lat = atan(sinh(.pi * (1 - 2 * row / pow(2, Double(z)))))
        unitsPerMetre = Projection.extent * pow(2, Double(z)) / (Projection.earthCircumference * cos(lat))
    }

    private var n: Double { pow(2, Double(z)) * Projection.extent }

    func metres(lon: Double, lat: Double) -> Vec2 {
        let mx = (lon + 180) / 360 * n
        let my = (1 - asinh(tan(lat * .pi / 180)) / .pi) / 2 * n
        return Vec2((mx - gx) / unitsPerMetre, (gy - my) / unitsPerMetre)
    }

    func lonLat(_ p: Vec2) -> (Double, Double) {
        let mx = gx + p.x * unitsPerMetre, my = gy - p.y * unitsPerMetre
        return (mx / n * 360 - 180, atan(sinh(.pi * (1 - 2 * my / n))) * 180 / .pi)
    }

    /// A tile's edges in local metres.
    func tileRect(x: Int, y: Int) -> (Vec2, Vec2) {
        let e = Projection.extent
        return (Vec2((Double(x) * e - gx) / unitsPerMetre, (gy - Double(y + 1) * e) / unitsPerMetre),
                Vec2((Double(x + 1) * e - gx) / unitsPerMetre, (gy - Double(y) * e) / unitsPerMetre))
    }
}

// MARK: Polygons

/// Twice the signed area: positive for a counter-clockwise ring.
func signedArea(_ ring: [Vec2]) -> Double {
    var s = 0.0
    for i in ring.indices {
        s += cross(ring[i], ring[(i + 1) % ring.count])
    }
    return s
}

/// The winding number of a ring around a point (non-zero: inside).
func winding(_ ring: [Vec2], _ p: Vec2) -> Int {
    var w = 0
    for i in ring.indices {
        let a = ring[i], b = ring[(i + 1) % ring.count]
        if a.y <= p.y {
            if b.y > p.y && cross(b - a, p - a) > 0 { w += 1 }
        } else if b.y <= p.y && cross(b - a, p - a) < 0 {
            w -= 1
        }
    }
    return w
}

/// The nearest point of the segment a-b to p, and where along it (0...1).
func nearestOnSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> (Vec2, Double) {
    let d = b - a
    let l2 = simd_length_squared(d)
    if l2 < 1e-18 { return (a, 0) }
    let t = max(0, min(1, simd_dot(p - a, d) / l2))
    return (a + d * t, t)
}

/// Douglas-Peucker: the points of an open run kept within `tolerance` of it.
func simplify(_ pts: [Vec2], tolerance: Double) -> [Vec2] {
    guard pts.count > 2 else { return pts }
    var keep = [Bool](repeating: false, count: pts.count)
    keep[0] = true
    keep[pts.count - 1] = true
    var stack = [(0, pts.count - 1)]
    while let (i, j) = stack.popLast() {
        var worst = -1.0, at = -1
        for k in (i + 1)..<j {
            let d = (nearestOnSegment(pts[k], pts[i], pts[j]).0 - pts[k]).length
            if d > worst { worst = d; at = k }
        }
        if at > 0 && worst > tolerance {
            keep[at] = true
            stack.append((i, at))
            stack.append((at, j))
        }
    }
    return pts.indices.filter { keep[$0] }.map { pts[$0] }
}

/// The corner `p1` between `p0` and `p2` replaced by an arc of `radius`,
/// tangent to both edges, a point every `step` degrees. The radius shrinks
/// when the edges are too short for it.
func fillet(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, radius: Double, step: Double = 10) -> [Vec2] {
    let u1 = (p0 - p1).normalized, u2 = (p2 - p1).normalized
    let cosT = max(-1, min(1, simd_dot(u1, u2)))
    let theta = acos(cosT)
    if theta < 1e-3 || theta > .pi - 1e-3 { return [p1] }
    var r = radius
    var t = r / tan(theta / 2)
    let room = 0.95 * min((p0 - p1).length, (p2 - p1).length)
    if t > room {
        t = room
        r = t * tan(theta / 2)
    }
    let t1 = p1 + u1 * t, t2 = p1 + u2 * t
    let bisector = (u1 + u2).normalized
    let centre = p1 + bisector * (r / sin(theta / 2))
    let a1 = (t1 - centre).angle, a2 = (t2 - centre).angle
    var sweep = a2 - a1
    while sweep > 180 { sweep -= 360 }
    while sweep < -180 { sweep += 360 }
    let count = max(2, Int((abs(sweep) / step).rounded(.up)))
    return (0...count).map { k in
        centre + Vec2.fromAngle(a1 + sweep * Double(k) / Double(count)) * r
    }
}

/// A polyline moved `d` to its left, each corner mitred (limited).
func offsetLine(_ pts: [Vec2], _ d: Double) -> [Vec2] {
    guard pts.count >= 2 else { return pts }
    return pts.indices.map { i in
        let a = i > 0 ? (pts[i] - pts[i - 1]).normalized.left : nil
        let b = i < pts.count - 1 ? (pts[i + 1] - pts[i]).normalized.left : nil
        guard let na = a ?? b, let nb = b ?? a else { return pts[i] }
        let m = (na + nb).normalized
        let c = max(0.3, simd_dot(m, na))
        return pts[i] + m * (d / c)
    }
}

/// The pieces of a polyline cut into dashes: `dash` long, `gap` between,
/// from its first point.
func dashes(_ pts: [Vec2], dash: Double, gap: Double) -> [[Vec2]] {
    var out: [[Vec2]] = []
    var current: [Vec2] = []
    var at = 0.0         // distance along the line
    var on = true
    var left = dash      // of the current dash or gap
    for i in 0..<(pts.count - 1) {
        var a = pts[i]
        let b = pts[i + 1]
        var seg = (b - a).length
        let dir = (b - a).normalized
        if on && current.isEmpty { current = [a] }
        while seg > 1e-9 {
            let take = min(seg, left)
            let p = a + dir * take
            if on { current.append(p) }
            seg -= take
            left -= take
            at += take
            a = p
            if left <= 1e-9 {
                if on {
                    if polylineLength(current) > 0.5 { out.append(current) }
                    current = []
                    on = false
                    left = gap
                } else {
                    on = true
                    left = dash
                    current = [a]
                }
            }
        }
    }
    if on && current.count >= 2 && polylineLength(current) > 0.5 { out.append(current) }
    return out
}

func polylineLength(_ pts: [Vec2]) -> Double {
    zip(pts, pts.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
}
