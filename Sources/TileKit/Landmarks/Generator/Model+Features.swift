import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// A recipe's features: colonnades, pediments, statues, boxes, steps.
extension LandmarkGenerator.Model {
    // MARK: Features

    func feature(_ f: LandmarkRecipe.Feature) {
        let colour = f.colour ?? "lm_white"
        let base = f.base ?? 0
        func p2(_ v: [Double]?) -> P2? { v.flatMap { $0.count == 2 ? P2($0[0], $0[1]) : nil } }
        switch f.kind {
        case "colonnade":
            guard let a = p2(f.from), let b = p2(f.to), let height = f.height, height > 1 else { return }
            let r = f.radius ?? 0.6, len = simd_length(b - a)
            let n = max(2, f.columns ?? Int(len / 3) + 1)
            let beam = min(1.0, height * 0.12), d = (b - a) / max(len, 1e-9)
            for i in 0..<n {
                let c = a + (b - a) * (Double(i) / Double(n - 1))
                let ring = (0..<8).map { k -> P2 in let t = Double(k) / 8 * 2 * .pi; return c + P2(cos(t), sin(t)) * r }
                prism(ring, base, base + height - beam, colour)
            }
            let side = P2(-d.y, d.x) * (r + 0.3), along = d * (r + 0.3)
            prism(ccw([a - along - side, b + along - side, b + along + side, a - along + side]), base + height - beam, base + height, colour)
        case "pediment":
            guard let a = p2(f.from), let b = p2(f.to), let height = f.height, height > 0 else { return }
            begin()
            let len = simd_length(b - a), d = (b - a) / max(len, 1e-9), n = P2(d.y, -d.x) * (f.depth ?? 1.5)
            let m = (a + b) / 2
            func v(_ p: P2, _ z: Double) -> V3 { V3(p.x, p.y, z) }
            let up = V3(0, 0, 1), dir = V3(d.x, d.y, 0), right = V3(n.x, n.y, 0)
            face([v(a + n, base), v(b + n, base), v(m + n, base + height)], right, colour)
            face([v(a, base), v(b, base), v(m, base + height)], -right, colour)
            face([v(a, base), v(a + n, base), v(m + n, base + height), v(m, base + height)], up - dir, colour)
            face([v(m, base + height), v(m + n, base + height), v(b + n, base), v(b, base)], up + dir, colour)
            face([v(a, base), v(b, base), v(b + n, base), v(a + n, base)], -up, colour)
        case "statue":
            guard let at = p2(f.at) else { return }
            let k = f.emphasis == true ? Caricature.emphasis : 1
            let h = (f.height ?? 4) * k, w = (f.width ?? h * 0.6 / k) * k
            let heading = (f.heading ?? 180) * .pi / 180
            // Facing, and its left.
            let u = P2(sin(heading), cos(heading)), v = P2(-u.y, u.x)
            var z = base
            if let pedestal = f.pedestal, pedestal > 0 {
                // A finial's pedestal (a star, a cross, a crescent, a flame) is a
                // post, a sculpture's a block (the
                // user, 2026-11-04: the Nikolskaya's star stood on a
                // platform in the air).
                let post = ["star", "cross", "crescent", "flame"].contains(f.shape ?? "")
                let side = post ? max(0.15, h * 0.06) : w
                box(at, u, v, side, side, z, z + pedestal, colour)
                z += pedestal
            }
            // Larger than life, finer: more sides to its round solids.
            roundSegments = k > 1 ? 16 : 10
            sculpture(f.shape ?? "figure", at, u, v, z, h, w, colour)
            roundSegments = 10
        case "box":
            let ring = (f.polygon ?? []).compactMap(p2)
            guard ring.count >= 3, let top = f.top, top > base else { return }
            prism(LandmarkGenerator.chamfered(ccw(ring), Caricature.chamfer), base, top, colour)
        case "steps":
            guard let a = p2(f.from), let b = p2(f.to), let height = f.height, height > 0 else { return }
            // A stack of slabs, the top one at the line, each a step deeper
            // than the one above: closed prisms the union joins.
            let len = simd_length(b - a), d = (b - a) / max(len, 1e-9), n = P2(d.y, -d.x)
            let count = max(1, f.count ?? Int(height / 0.16)), depth = f.depth ?? Double(count) * 0.35
            for i in 0..<count {
                let reach = depth * Double(i + 1) / Double(count), top = base + height * Double(count - i) / Double(count)
                prism(ccw([a, b, b + n * reach, a + n * reach]), base, top, colour)
            }
        default:
            break
        }
    }
}
