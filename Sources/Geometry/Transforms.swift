import simd

/// What `Geometry` does in Swift itself, on its coordinates: moving,
/// turning, scaling, orienting, cutting a line.
extension Geometry {
    /// Every coordinate moved by `f`, the structure kept.
    public func map(_ f: (P2) -> P2) -> Geometry {
        switch kind {
        case .point: return .point(f(xy))
        case .lineString: return .lineString(coords.map(f))
        case .linearRing: return .lineString(coords.map(f))
        case .polygon: return .polygon(exterior.map(f), holes: interiors.map { $0.map(f) })
        default: return .collection(parts.map { $0.map(f) })
        }
    }

    public func translate(_ dx: Double, _ dy: Double) -> Geometry { map { $0 + P2(dx, dy) } }

    /// Turned by `degrees` (or radians) about `origin`.
    public func rotate(_ angle: Double, origin: P2, radians: Bool = false) -> Geometry {
        let r = radians ? angle : angle * .pi / 180
        let c = cos(r), s = sin(r)
        return map { p in
            let d = p - origin
            return origin + P2(d.x * c - d.y * s, d.x * s + d.y * c)
        }
    }

    public func scale(_ sx: Double, _ sy: Double, origin: P2) -> Geometry {
        map { origin + ($0 - origin) * P2(sx, sy) }
    }

    /// A polygon with its outer ring counter-clockwise (sign 1) or clockwise
    /// (-1), its holes the other way, as shapely's `orient`.
    public func oriented(_ sign: Double = 1) -> Geometry {
        guard kind == .polygon else { return .collection(parts.map { $0.oriented(sign) }) }
        func wound(_ r: [P2], ccw: Bool) -> [P2] { (signedArea(r) > 0) == ccw ? r : r.reversed() }
        return .polygon(wound(exterior, ccw: sign > 0), holes: interiors.map { wound($0, ccw: sign < 0) })
    }

    /// The part of a line from `start` to `end` along it, as shapely's
    /// `substring`.
    public func substring(_ start: Double, _ end: Double) -> Geometry {
        let pts = coords
        guard pts.count >= 2 else { return self }
        var out: [P2] = []
        var at = 0.0
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let l = simd_length(b - a)
            let s0 = at, s1 = at + l
            if s1 >= start && s0 <= end && l > 0 {
                let t0 = max(0, (start - s0) / l), t1 = min(1, (end - s0) / l)
                let p0 = a + (b - a) * t0, p1 = a + (b - a) * t1
                if out.isEmpty || out.last! != p0 { out.append(p0) }
                if out.last! != p1 { out.append(p1) }
            }
            at = s1
        }
        return out.count >= 2 ? .lineString(out) : .point(out.first ?? pts[0])
    }
}

/// Twice the signed area of a ring: positive when counter-clockwise.
public func signedArea(_ r: [P2]) -> Double {
    guard r.count >= 3 else { return 0 }
    var s = 0.0
    for i in 0..<r.count {
        let a = r[i], b = r[(i + 1) % r.count]
        s += a.x * b.y - a.y * b.x
    }
    return s
}
