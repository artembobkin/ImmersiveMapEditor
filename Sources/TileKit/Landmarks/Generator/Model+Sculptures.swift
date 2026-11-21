import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// The sculptures: what a statue feature or shape is built of (a figure,
/// a horse, a chariot, a star, an obelisk, a cross) from round solids,
/// sweeps through rings, tubes, balls and tori.
extension LandmarkGenerator.Model {
    // MARK: Sculptures

    /// A box standing on `c`, `lu` along `u` by `lv` along `v`.
    func box(_ c: P2, _ u: P2, _ v: P2, _ lu: Double, _ lv: Double, _ z0: Double, _ z1: Double, _ colour: String) {
        let a = u * (lu / 2), b = v * (lv / 2)
        prism(ccw([c - a - b, c + a - b, c + a + b, c - a + b]), z0, z1, colour)
    }

    /// A sculpture of a shape, `h` tall, facing `u`, standing at `c` on `z`.
    /// Figures, horses and chariots are round solids (tubes and balls
    /// swept along a skeleton), so they read as what they are from
    /// across the square (the user, 2026-10-28: a quadriga of boxes
    /// read as a shelf of blocks).
    func sculpture(_ shape: String, _ c: P2, _ u: P2, _ v: P2, _ z: Double, _ h: Double, _ w: Double, _ colour: String) {
        switch shape {
        case "horse":
            horse(c, u, v, z, h, colour)
        case "quadriga":
            let hh = h * 0.72, step = max(w, hh * 1.4) / 4
            for k in 0..<4 { horse(c + u * (h * 0.25) + v * ((Double(k) - 1.5) * step), u, v, z, hh, colour, raised: k % 2 == 0 ? 1 : -1) }
            chariot(c - u * (h * 0.7), u, v, z, h * 0.6, colour)
            figure(c - u * (h * 0.74), u, v, z + h * 0.06 + h * 0.6 * 0.12, h * 0.6, colour)
        case "equestrian":
            let hh = h * 0.72, fh = h * 0.45
            horse(c, u, v, z, hh, colour, raised: 1)
            figure(c + u * (hh * 0.05), u, v, z + hh * 0.72 - fh * 0.5, fh, colour, riding: true)
        case "obelisk":
            let a = u * (w / 2), b = v * (w / 2)
            loft(ccw([c - a - b, c + a - b, c + a + b, c - a + b]), c, z, [(1, 0), (0.62, h * 0.86), (0, h)], colour)
        case "cross":
            // A post and a bar, their ends flared, and the ball at its
            // foot (the user, 2026-11-04: a finial drawn larger than life
            // asks for its detail).
            let t = max(0.08, h * 0.08), bar = z + h * 0.68
            box(c, u, v, t, t, z, z + h, colour)
            box(c, u, v, t, h * 0.6, bar, bar + t, colour)
            box(c, u, v, t * 1.8, t * 1.8, z + h - t * 1.5, z + h, colour)
            for side in [-1.0, 1.0] {
                box(c + v * (side * (h * 0.3 - t * 0.75)), u, v, t * 1.8, t * 1.5, bar - t * 0.4, bar + t * 1.4, colour)
            }
            ball(V3(c.x, c.y, z + t * 1.2), t * 1.4, colour)
        case "crescent":
            // A crescent with a star in it, a mosque's finial: an arc of
            // a ring thickest at its foot and pointed at its horns,
            // open at the top, on a pole from its foot (the user,
            // 2026-11-04: Istiqlal's came out as a star in a full ring).
            let big = h / 2, thick = max(0.06, big * 0.22), post = max(0.06, h * 0.04)
            let zc = z + h * 0.15 + big
            let centre = V3(c.x, c.y, zc), U = V3(u.x, u.y, 0), V = V3(v.x, v.y, 0), W = V3(0, 0, 1)
            tube(V3(c.x, c.y, z), V3(c.x, c.y, zc - big * 0.5), post, post, segments: 8, colour)
            let m = 20, from = 50.0 * .pi / 180, to = 310.0 * .pi / 180
            let rings = (0...m).map { k -> [V3] in
                let s = Double(k) / Double(m), phi = from + (to - from) * s
                let radial = V * sin(phi) + W * cos(phi)
                let r = max(0.02, thick * sin(.pi * s))
                return ring(centre + radial * big, U, radial, r, r, 8)
            }
            sweep(rings, colour)
            star(c, u, v, zc, big * 0.42, colour)
        case "flame":
            // A gilded flame, as on a monument's tip: a teardrop lofted
            // from a round foot to a point (any country's finial, the
            // user, 2026-11-04).
            let r = min(w, h * 0.6) / 2
            let foot = (0..<12).map { k -> P2 in let t = 2 * Double.pi * Double(k) / 12; return c + P2(r * cos(t), r * sin(t)) }
            loft(foot, c, z, [(0.55, 0), (1, h * 0.3), (0.72, h * 0.62), (0.3, h * 0.85), (0, h)], colour)
        case "star":
            // On a pole from its foot to its middle, through the notch
            // between its lower points: a star is mounted, never left
            // hanging over a spire's tip (the user, 2026-11-04: the
            // Spasskaya's star, drawn larger, hung in the air).
            let t = max(0.06, h * 0.04)
            tube(V3(c.x, c.y, z), V3(c.x, c.y, z + h / 2), t, t, segments: 8, colour)
            star(c, u, v, z + h / 2, h / 2, colour)
        default:
            figure(c, u, v, z, h, colour)
        }
    }

    // MARK: Round solids

    /// A ring of `n` points about `c`, `ru` along `a` and `rv` along `b`.
    func ring(_ c: V3, _ a: V3, _ b: V3, _ ru: Double, _ rv: Double, _ n: Int) -> [V3] {
        (0..<n).map { k in let t = 2 * .pi * Double(k) / Double(n); return c + a * (ru * cos(t)) + b * (rv * sin(t)) }
    }

    /// A closed solid swept through rings of one count: the sides
    /// between neighbouring rings, and, unless the sweep closes on
    /// itself, a fan cap at each end. A ring of radius 0 is a tip.
    func sweep(_ rings: [[V3]], closed: Bool = false, _ colour: String) {
        guard rings.count >= 2, let n = rings.first?.count, n >= 3 else { return }
        begin()
        func centre(_ r: [V3]) -> V3 { r.reduce(V3(repeating: 0), +) / Double(r.count) }
        if !closed {
            let c0 = centre(rings[0]), c1 = centre(rings[rings.count - 1])
            let axis0 = c0 - centre(rings[1]), axis1 = c1 - centre(rings[rings.count - 2])
            for k in 0..<n { tri(c0, rings[0][k], rings[0][(k + 1) % n], axis0, colour) }
            for k in 0..<n { tri(c1, rings[rings.count - 1][k], rings[rings.count - 1][(k + 1) % n], axis1, colour) }
        }
        let last = closed ? rings.count : rings.count - 1
        for i in 0..<last {
            let a = rings[i], b = rings[(i + 1) % rings.count], mid = (centre(a) + centre(b)) / 2
            for k in 0..<n {
                let k1 = (k + 1) % n
                let out = (a[k] + a[k1] + b[k] + b[k1]) / 4 - mid
                tri(a[k], a[k1], b[k1], out, colour)
                tri(a[k], b[k1], b[k], out, colour)
            }
        }
    }

    /// A straight round tube from `p` to `q`, `r0` thick at `p`, `r1` at `q`.
    func tube(_ p: V3, _ q: V3, _ r0: Double, _ r1: Double, segments given: Int? = nil, _ colour: String) {
        let n = given ?? roundSegments
        let d = q - p, len = simd_length(d)
        guard len > 1e-6 else { return }
        let t = d / len, helper = abs(t.z) < 0.9 ? V3(0, 0, 1) : V3(1, 0, 0)
        let a = simd_normalize(simd_cross(t, helper)), b = simd_cross(t, a)
        sweep([ring(p, a, b, r0, r0, n), ring(q, a, b, r1, r1, n)], colour)
    }

    /// A ball.
    func ball(_ c: V3, _ r: Double, segments given: Int? = nil, _ colour: String) {
        let n = given ?? roundSegments
        let m = max(3, n / 2)
        let rings = (0...m).map { j -> [V3] in
            let phi = .pi * Double(j) / Double(m)
            return ring(c + V3(0, 0, r * cos(phi)), V3(1, 0, 0), V3(0, 1, 0), r * sin(phi), r * sin(phi), n)
        }
        sweep(rings, colour)
    }

    /// A ring solid: a circle of radius `big` in the plane of `a` and
    /// `b` about `c`, `small` thick.
    func torus(_ c: V3, _ a: V3, _ b: V3, _ big: Double, _ small: Double, segments n: Int = 16, section m: Int = 8, _ colour: String) {
        let w = simd_normalize(simd_cross(a, b))
        let rings = (0..<n).map { k -> [V3] in
            let t = 2 * .pi * Double(k) / Double(n), e = a * cos(t) + b * sin(t)
            return ring(c + e * big, e, w, small, small, m)
        }
        sweep(rings, closed: true, colour)
    }

    /// A standing person `h` tall facing `u`: legs, hips, a torso
    /// widening to the shoulders, arms (one raised forward), a neck and
    /// a head. Riding, the legs hang down the sides of the mount.
    func figure(_ c: P2, _ u: P2, _ v: P2, _ z: Double, _ h: Double, _ colour: String, riding: Bool = false) {
        let U = V3(u.x, u.y, 0), V = V3(v.x, v.y, 0), W = V3(0, 0, 1)
        func p(_ a: Double, _ b: Double, _ d: Double) -> V3 { V3(c.x, c.y, z) + U * (a * h) + V * (b * h) + W * (d * h) }
        for side in [-1.0, 1.0] {
            if riding {
                tube(p(0, side * 0.08, 0.5), p(0.1, side * 0.2, 0.3), h * 0.065, h * 0.045, colour)
                ball(p(0.1, side * 0.2, 0.3), h * 0.05, colour)
                tube(p(0.1, side * 0.2, 0.3), p(0.02, side * 0.22, 0.05), h * 0.045, h * 0.035, colour)
            } else {
                tube(p(0, side * 0.07, 0.5), p(0.02, side * 0.08, 0.05), h * 0.07, h * 0.045, colour)
                tube(p(-0.03, side * 0.08, 0.03), p(0.12, side * 0.08, 0.03), h * 0.035, h * 0.03, colour)
            }
        }
        ball(p(0, 0, 0.5), h * 0.1, colour)
        sweep([ring(p(0, 0, 0.48), V, U, h * 0.12, h * 0.09, 10), ring(p(0, 0, 0.66), V, U, h * 0.15, h * 0.1, 10),
               ring(p(0, 0, 0.8), V, U, h * 0.17, h * 0.1, 10)], colour)
        for side in [-1.0, 1.0] { ball(p(0, side * 0.17, 0.78), h * 0.06, colour) }
        // The right arm raised forward (the reins), the left down and out.
        tube(p(0, -0.17, 0.78), p(0.22, -0.2, 0.88), h * 0.05, h * 0.04, colour)
        ball(p(0.22, -0.2, 0.88), h * 0.045, colour)
        tube(p(0, 0.17, 0.78), p(0.05, 0.25, 0.5), h * 0.05, h * 0.04, colour)
        ball(p(0.05, 0.25, 0.5), h * 0.045, colour)
        tube(p(0, 0, 0.8), p(0, 0, 0.89), h * 0.05, h * 0.045, colour)
        ball(p(0, 0, 0.92), h * 0.08, colour)
    }

    /// A horse `h` tall to the top of its head, facing `u`: a barrel
    /// body, an arched neck, the head with its ears, four jointed legs
    /// (`raised`: the left or right foreleg lifted, 1 or -1, 0 for
    /// standing) and a tail.
    func horse(_ c: P2, _ u: P2, _ v: P2, _ z: Double, _ h: Double, _ colour: String, raised: Int = 0) {
        let U = V3(u.x, u.y, 0), V = V3(v.x, v.y, 0), W = V3(0, 0, 1)
        func p(_ a: Double, _ b: Double, _ d: Double) -> V3 { V3(c.x, c.y, z) + U * (a * h) + V * (b * h) + W * (d * h) }
        // The body: sections from the chest to the rump.
        let sections: [(Double, Double, Double, Double)] = [(0.5, 0.63, 0.06, 0.07), (0.4, 0.62, 0.14, 0.17), (0.1, 0.6, 0.15, 0.19),
                                                            (-0.2, 0.6, 0.15, 0.19), (-0.42, 0.63, 0.12, 0.16), (-0.5, 0.66, 0.05, 0.06)]
        sweep(sections.map { ring(p($0.0, 0, $0.1), V, W, $0.2 * h, $0.3 * h, 12) }, colour)
        // The neck, arched up and forward, and the head.
        sweep([ring(p(0.3, 0, 0.68), V, U, h * 0.1, h * 0.12, 10), ring(p(0.45, 0, 0.83), V, U, h * 0.085, h * 0.11, 10),
               ring(p(0.58, 0, 0.93), V, U, h * 0.07, h * 0.08, 10)], colour)
        ball(p(0.58, 0, 0.93), h * 0.075, colour)
        tube(p(0.58, 0, 0.93), p(0.8, 0, 0.8), h * 0.07, h * 0.045, colour)
        for side in [-1.0, 1.0] { tube(p(0.55, side * 0.035, 0.96), p(0.56, side * 0.05, 1.03), h * 0.022, 0, segments: 6, colour) }
        // The legs: shoulder or hip, a jointed upper and lower leg, a hoof.
        for (a, front) in [(0.33, true), (-0.3, false)] {
            for side in [-1.0, 1.0] {
                let b = side * 0.09
                let lift = front && Int(side) == raised
                let knee = lift ? p(a + 0.12, b, 0.36) : p(a, b, 0.28)
                let hoof = lift ? p(a + 0.04, b, 0.2) : p(a + (front ? 0.02 : -0.02), b, 0.02)
                tube(p(a, b, 0.52), knee, h * 0.06, h * 0.042, colour)
                ball(knee, h * 0.045, colour)
                tube(knee, hoof, h * 0.04, h * 0.035, colour)
                tube(hoof + W * (h * 0.02), hoof - W * (h * 0.02), h * 0.045, h * 0.045, segments: 8, colour)
            }
        }
        // The tail.
        tube(p(-0.5, 0, 0.66), p(-0.64, 0, 0.3), h * 0.05, h * 0.02, segments: 8, colour)
    }

    /// A chariot `h` tall at its rim, facing `u`: a floor, a curved
    /// front, an axle and two spoked wheels.
    func chariot(_ c: P2, _ u: P2, _ v: P2, _ z: Double, _ h: Double, _ colour: String) {
        let U = V3(u.x, u.y, 0), V = V3(v.x, v.y, 0), W = V3(0, 0, 1)
        func p(_ a: Double, _ b: Double, _ d: Double) -> V3 { V3(c.x, c.y, z) + U * (a * h) + V * (b * h) + W * (d * h) }
        box(c, u, v, h * 0.9, h * 0.9, z + h * 0.12, z + h * 0.2, colour)
        // The front: an arc of a ring in plan, a wall from the floor to the rim.
        let r = h * 0.45, t = h * 0.08, n = 12
        let outer = (0...n).map { k -> P2 in let a = -1.9 + 3.8 * Double(k) / Double(n); return c + u * (r * cos(a)) + v * (r * sin(a)) }
        let inner = (0...n).map { k -> P2 in let a = -1.9 + 3.8 * Double(k) / Double(n); return c + u * ((r - t) * cos(a)) + v * ((r - t) * sin(a)) }
        prism(ccw(outer + inner.reversed()), z + h * 0.12, z + h, colour)
        // The axle and the wheels.
        tube(p(-0.15, -0.62, 0.4), p(-0.15, 0.62, 0.4), h * 0.04, h * 0.04, segments: 8, colour)
        for side in [-1.0, 1.0] {
            let hub = p(-0.15, side * 0.58, 0.4)
            torus(hub, U, W, h * 0.4, h * 0.04, colour)
            ball(hub, h * 0.07, colour)
            for k in 0..<8 {
                let a = Double(k) * .pi / 4
                tube(hub, hub + (U * cos(a) + W * sin(a)) * (h * 0.38), h * 0.02, h * 0.02, segments: 6, colour)
            }
        }
    }

    /// A five-pointed star standing upright, its face toward `u`, `r`
    /// to a point, centred at `zc`.
    /// A faceted star, as the Kremlin's: a ridge along each ray from a
    /// raised middle to its sharp tip, the valleys between the rays
    /// sharp, front and back alike, twenty facets in one closed solid
    /// (the user, 2026-11-04: a flat plate drawn larger than life asked
    /// for the detail its size shows).
    func star(_ c: P2, _ u: P2, _ v: P2, _ zc: Double, _ r: Double, _ colour: String) {
        begin()
        let t = max(0.08, r * 0.28)
        let pts: [(P2, Double)] = (0..<10).map { k in
            let rr = k % 2 == 0 ? r : r * 0.4, a = Double.pi / 2 + Double(k) * .pi / 5
            return (c + v * (rr * cos(a)), zc + rr * sin(a))
        }
        func p(_ q: (P2, Double), _ depth: Double) -> V3 { let s = q.0 + u * depth; return V3(s.x, s.y, q.1) }
        for side in [1.0, -1.0] {
            let apex = p((c, zc), side * t)
            for k in 0..<10 {
                let e0 = pts[k], e1 = pts[(k + 1) % 10]
                let mid = ((e0.0 + e1.0) / 2 - c, (e0.1 + e1.1) / 2 - zc)
                let hint = V3(u.x * side + mid.0.x * 0.3, u.y * side + mid.0.y * 0.3, mid.1 * 0.3)
                tri(apex, p(e0, 0), p(e1, 0), hint, colour)
            }
        }
    }
}
