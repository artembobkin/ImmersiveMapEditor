import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// The plan's small helpers: a ring counter-clockwise, chamfered,
/// grown, and which way an edge looks.
extension LandmarkGenerator {
    // MARK: Plan helpers

    static func ccw(_ ring: [P2]) -> [P2] {
        var r = ring
        if r.count > 1, simd_length(r[0] - r[r.count - 1]) < 1e-9 { r.removeLast() }
        return signedArea(r) < 0 ? r.reversed() : r
    }

    /// A counter-clockwise ring grown outward by `d`, square at its corners.
    /// A counter-clockwise ring with every convex corner turning more than
    /// 25° cut across: the corner's point replaced by two, `c` along each
    /// of its edges (a third of the shorter edge at most). A concave corner
    /// (a courtyard's, a re-entrant one) is left as it is.
    static func chamfered(_ ring: [P2], _ c: Double) -> [P2] {
        let n = ring.count
        guard n >= 3, c > 0.01 else { return ring }
        var out: [P2] = []
        for i in 0..<n {
            let p = ring[(i + n - 1) % n], q = ring[i], r = ring[(i + 1) % n]
            let a = q - p, b = r - q, la = simd_length(a), lb = simd_length(b)
            guard la > 1e-6, lb > 1e-6 else { out.append(q); continue }
            let cross = a.x * b.y - a.y * b.x
            let turn = atan2(cross, simd_dot(a, b)) * 180 / .pi
            guard turn > 25 else { out.append(q); continue }
            let d = min(c, la / 3, lb / 3)
            guard d > 0.05 else { out.append(q); continue }
            out.append(q - a / la * d)
            out.append(q + b / lb * d)
        }
        return out
    }

    static func grown(_ ring: [P2], _ d: Double) -> [P2] {
        let g = Geometry.polygon(ring + [ring[0]]).buffer(d, quadSegs: 1, join: .mitre).polygons
            .max { $0.area < $1.area }
        return g.map { ccw(Array($0.exterior.dropLast())) } ?? ring
    }

    /// Which way an edge of a counter-clockwise ring looks: its right.
    static func outward(_ a: P2, _ b: P2) -> V3 {
        let d = b - a
        return V3(d.y, -d.x, 0) / max(simd_length(d), 1e-9)
    }

    /// Which way an edge of an outline looks: away from the outline's inside.
    static func outwardOf(_ outline: Geometry, _ a: P2, _ b: P2) -> V3 {
        let o = outward(a, b), m = (a + b) / 2
        return outline.contains(m + P2(o.x, o.y) * 0.01) ? -o : o
    }
}

extension LandmarkGenerator.Model {
    func outward(_ a: P2, _ b: P2) -> V3 { LandmarkGenerator.outward(a, b) }
    func grown(_ ring: [P2], _ d: Double) -> [P2] { LandmarkGenerator.grown(ring, d) }
    func ccw(_ ring: [P2]) -> [P2] { LandmarkGenerator.ccw(ring) }
    func outwardOf(_ o: Geometry, _ a: P2, _ b: P2) -> V3 { LandmarkGenerator.outwardOf(o, a, b) }
}
