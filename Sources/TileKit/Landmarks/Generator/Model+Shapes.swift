import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// A recipe's shapes: boxes, cylinders, cones, spheres, prisms, lofts,
/// rings and lettering, each placed by its frame (where it stands, which
/// way it faces, how it leans).
extension LandmarkGenerator.Model {
    // MARK: Shapes

    /// A shape's local frame: its origin at its place on its base, U
    /// along its heading, V to the left, W up, tipped by its pitch.
    struct Frame {
        let o, U, V, W: V3
        func p(_ a: Double, _ b: Double, _ c: Double) -> V3 { o + U * a + V * b + W * c }
        func dir(_ a: Double, _ b: Double, _ c: Double) -> V3 { U * a + V * b + W * c }
    }

    /// A text's letters as solids: each letter's outlines from the Mac's
    /// bold sans face (any script), flattened and simplified to a low-poly
    /// ring, extruded `depth` thick, standing upright on the frame's base
    /// and facing its heading, the whole centred on its origin.
    func letters(_ text: String, height: Double, depth: Double, _ f: Frame, _ colour: String) {
        let glyphs = LandmarkGenerator.glyphs(text, height: height)
        let width = glyphs.reduce(0) { $0 + $1.advance }
        var pen = -width / 2
        // Along the text is the frame's left (a reader before the sign has
        // it on the right), up its up, the front toward its heading.
        func p(_ u: Double, _ v: Double, _ w: Double) -> V3 { f.o + f.V * u + f.W * v + f.U * w }
        for g in glyphs {
            defer { pen += g.advance }
            for (outer, holes) in g.letters {
                begin()
                let shift = P2(pen, 0)
                let ring = outer.map { $0 + shift }, hs = holes.map { $0.map { $0 + shift } }
                let shape = Geometry.polygon(ring + [ring[0]], holes: hs.map { $0 + [$0[0]] })
                for t in shape.constrainedDelaunay() where t.count == 3 {
                    tri(p(t[0].x, t[0].y, depth), p(t[1].x, t[1].y, depth), p(t[2].x, t[2].y, depth), f.U, colour)
                    tri(p(t[0].x, t[0].y, 0), p(t[1].x, t[1].y, 0), p(t[2].x, t[2].y, 0), -f.U, colour)
                }
                for r in [ring] + hs {
                    for i in r.indices {
                        let a = r[i], b = r[(i + 1) % r.count], d = b - a
                        guard simd_length(d) > 1e-9 else { continue }
                        // Outward of a counter-clockwise outer ring is its right; the
                        // holes run clockwise, so their right is outward too.
                        let hint = f.V * d.y - f.W * d.x
                        face([p(a.x, a.y, 0), p(b.x, b.y, 0), p(b.x, b.y, depth), p(a.x, a.y, depth)], hint, colour)
                    }
                }
            }
        }
    }

    func frame(_ at: P2, _ base: Double, _ heading: Double, _ pitch: Double) -> Frame {
        let h = heading * .pi / 180, p = pitch * .pi / 180
        let u = V3(sin(h), cos(h), 0), v = V3(-cos(h), sin(h), 0), w = V3(0, 0, 1)
        return Frame(o: V3(at.x, at.y, base), U: u * cos(p) + w * sin(p), V: v, W: w * cos(p) - u * sin(p))
    }

    /// A shape, with its copies in a row or around a point.
    func shape(_ s: LandmarkRecipe.Shape, _ source: LandmarkSource) {
        let at = s.at.flatMap { $0.count == 2 ? P2($0[0], $0[1]) : nil } ?? .zero
        var places: [(P2, Double, Double)] = [(at, s.heading ?? 0, 0)]
        if let a = s.around, a.count >= 1, a.centre.count == 2 {
            let c = P2(a.centre[0], a.centre[1])
            places = (0..<a.count).map { k in
                let turn = 2 * .pi * Double(k) / Double(a.count), d = at - c
                let q = c + P2(d.x * cos(turn) + d.y * sin(turn), -d.x * sin(turn) + d.y * cos(turn))
                return (q, (s.heading ?? 0) + turn * 180 / .pi, 0)
            }
        }
        if let r = s.repeat, r.count >= 1, r.step.count == 3 {
            places = places.flatMap { place in (0..<r.count).map { k in
                (place.0 + P2(r.step[0], r.step[1]) * Double(k), place.1, place.2 + r.step[2] * Double(k)) } }
        }
        for (p, heading, rise) in places { one(s, source, at: p, heading: heading, base: (s.base ?? 0) + rise) }
    }

    func one(_ given: LandmarkRecipe.Shape, _ source: LandmarkSource, at: P2, heading: Double, base: Double) {
        begin()
        // What makes the building recognisable, a size up.
        var s = given
        // Only a finial standing free, a ring (a star's) or a ball, grows:
        // the one rule of emphasis, for every city (the user, 2026-11-04,
        // after lettering, a tower's cone, a lantern's dome and a star's
        // platform were each drawn larger and each was wrong): a
        // sculpture or a finial about its foot, never the building's own
        // body, roof or cap, which is told by its real size.
        if s.emphasis == true, ["ring", "sphere"].contains(s.kind) {
            let k = Caricature.emphasis
            s.size = s.size.map { $0.map { $0 * k } }
            s.radius = s.radius.map { $0 * k }
            s.radius_top = s.radius_top.map { $0 * k }
            s.height = s.height.map { $0 * k }
            s.profile = s.profile.map { $0.map { $0.count == 2 ? [$0[0], $0[1] * k] : $0 } }
        }
        let colour = s.colour ?? "lm_stone", n = max(3, min(64, s.segments ?? 16))
        let f = frame(at, base, heading, s.pitch ?? 0)
        func circle(_ r: Double) -> [P2] { (0..<n).map { k in let t = 2 * .pi * Double(k) / Double(n); return P2(r * cos(t), r * sin(t)) } }
        // A ring in plan, moved by the shape's place when it is its own.
        func ring() -> [P2]? {
            if let o = s.outline, let r = source.ring(o) { return ccw(r) }
            if let poly = s.polygon?.filter({ $0.count == 2 }).map({ P2($0[0], $0[1]) }), poly.count >= 3 { return ccw(poly) }
            return nil
        }
        switch s.kind {
        case "text":
            guard let text = s.text, let height = s.height, height > 0 else { return }
            letters(text, height: height, depth: max(0.1, s.depth ?? 0.4), f, colour)
        case "ring":
            // Upright, its face toward the heading, its lowest point on the
            // base; a pitch of 90 lays it flat.
            guard let radius = s.radius, radius > 0 else { return }
            let thick = max(0.1, s.depth ?? radius * 0.1)
            torus(f.p(0, 0, radius + thick), f.V, f.W, radius, thick, segments: n, section: max(4, min(12, n / 2)), colour)
        case "box":
            guard let size = s.size, size.count == 3 else { return }
            let (a, b, c) = (size[0] / 2, size[1] / 2, size[2])
            let corners = [(-a, -b), (a, -b), (a, b), (-a, b)]
            let upright = (s.pitch ?? 0) == 0
            let ring = ccw(corners.map { let q = f.p($0.0, $0.1, 0); return P2(q.x, q.y) })
            if upright, s.doors != nil || s.windows != nil {
                // A podium, a porch or a wing drawn as a box takes doors
                // and windows as a mass does: entrances cut in, never a
                // dark plate laid on the wall (the user, 2026-11-02: the
                // Prosecutor General's doors stood proud of its podium).
                walls(ring, base, base + c, colour, windows: s.windows, doors: place(s.doors ?? [], on: ring))
                cap(ring, base, up: false, colour)
                cap(ring, base + c, up: true, colour)
            } else {
                face(corners.map { f.p($0.0, $0.1, 0) }, f.dir(0, 0, -1), colour)
                face(corners.map { f.p($0.0, $0.1, c) }, f.dir(0, 0, 1), colour)
                for k in 0..<4 {
                    let (p0, p1) = (corners[k], corners[(k + 1) % 4])
                    let mid = ((p0.0 + p1.0) / 2, (p0.1 + p1.1) / 2)
                    face([f.p(p0.0, p0.1, 0), f.p(p1.0, p1.1, 0), f.p(p1.0, p1.1, c), f.p(p0.0, p0.1, c)], f.dir(mid.0, mid.1, 0), colour)
                }
            }
            // An upright glass box is glazed: a bay, a curtain wall.
            if LandmarkRecipe.glassColours.contains(colour), upright {
                glazing(ring, base, base + c, spacing: s.mullions, frame: s.frame)
            }
        case "cylinder", "cone":
            guard var r = s.radius, var h = s.height else { return }
            var rt = s.kind == "cone" ? (s.radius_top ?? 0) : (s.radius_top ?? r)
            if s.kind == "cone" {
                // A pinnacle, not a spike: wide enough at the foot, blunt
                // at the tip, not too tall for its width.
                r = max(r, Caricature.spireRadius)
                rt = max(rt, r * Caricature.spireTip)
                h = min(h, r * Caricature.spireAspect)
            }
            let lo = circle(r), hi = circle(rt)
            if s.kind == "cylinder", (s.pitch ?? 0) == 0, abs(r - rt) < 1e-6, let w = s.windows, w.storeys >= 1, h > 1 {
                // A round bay with a ribbon of windows a storey between
                // its parapets: the glass a band recessed into the drum,
                // a post at every facet (the user, 2026-11-04: a tower's
                // rounded bays, glazed in the photo, came out as plain
                // red drums, since only a box or a prism took windows).
                let storey = h / Double(w.storeys)
                let band = min(max(w.height * Caricature.windowRise, 1.2), storey * 0.65)
                let ring = ccw(lo.map { let q = f.p($0.x, $0.y, 0); return P2(q.x, q.y) })
                let inner = ccw(circle(max(r - LandmarkGenerator.windowDepth, r * 0.6)).map { let q = f.p($0.x, $0.y, 0); return P2(q.x, q.y) })
                let glass = "\(colour).glass", post = w.colour ?? "lm_white", postSide = Caricature.mullion
                for k in 0..<w.storeys {
                    let z0 = base + storey * Double(k), z1 = z0 + storey - band, z2 = z0 + storey
                    prism(ring, z0, z1, colour)
                    prism(inner, z1, z2, glass)
                    for p in inner { box(p, P2(1, 0), P2(0, 1), postSide, postSide, z1, z2, post) }
                }
                return
            }
            for k in 0..<n {
                let (p0, p1) = (lo[k], lo[(k + 1) % n]), (q0, q1) = (hi[k], hi[(k + 1) % n])
                let mid = (p0 + p1) / 2
                let quad = [f.p(p0.x, p0.y, 0), f.p(p1.x, p1.y, 0), f.p(q1.x, q1.y, h), f.p(q0.x, q0.y, h)]
                face(quad.reduce(into: [V3]()) { out, p in if out.last.map({ simd_length($0 - p) > 1e-9 }) ?? true { out.append(p) } },
                     f.dir(mid.x, mid.y, (r - rt) / max(h, 1e-9) * r), colour)
            }
            face(lo.reversed().map { f.p($0.x, $0.y, 0) }, f.dir(0, 0, -1), colour)
            if rt > 1e-6 { face(hi.map { f.p($0.x, $0.y, h) }, f.dir(0, 0, 1), colour) }
            // An upright glass cylinder is glazed: a rotunda, a glass
            // tower, a mullion at every segment.
            if LandmarkRecipe.glassColours.contains(colour), s.kind == "cylinder", abs(r - rt) < 1e-6, (s.pitch ?? 0) == 0 {
                let ring = ccw(lo.map { let q = f.p($0.x, $0.y, 0); return P2(q.x, q.y) })
                glazing(ring, base, base + h, spacing: s.mullions ?? 2 * .pi * r / Double(n), frame: s.frame)
            }
        case "sphere", "dome":
            guard let r = s.radius else { return }
            let bands = max(2, n / 2), whole = s.kind == "sphere"
            let centre = f.p(0, 0, whole ? r : 0)
            func at(_ i: Int, _ j: Int) -> V3 {
                let phi = whole ? -.pi / 2 + .pi * Double(i) / Double(bands) : .pi / 2 * Double(i) / Double(bands)
                let theta = 2 * .pi * Double(j) / Double(n)
                return f.p(r * cos(phi) * cos(theta), r * cos(phi) * sin(theta), (whole ? r : 0) + r * sin(phi))
            }
            for i in 0..<bands {
                for j in 0..<n {
                    let quad = [at(i, j), at(i, j + 1), at(i + 1, j + 1), at(i + 1, j)]
                    let pts = quad.reduce(into: [V3]()) { out, p in if out.allSatisfy({ simd_length($0 - p) > 1e-9 }) { out.append(p) } }
                    guard pts.count >= 3 else { continue }
                    face(pts, pts.reduce(V3.zero, +) / Double(pts.count) - centre, colour)
                }
            }
            if !whole { face((0..<n).reversed().map { at(0, $0) }, f.dir(0, 0, -1), colour) }
        case "prism":
            guard let outer = ring(), let top = s.top, top > base else { return }
            let holes = (s.holes ?? []).map { ccw($0.filter { $0.count == 2 }.map { P2($0[0], $0[1]) }) }.filter { $0.count >= 3 }
            walls(outer, base, top, colour, windows: s.windows, doors: place(s.doors ?? [], on: outer))
            for hole in holes { walls(hole.reversed(), base, top, colour) }
            cap(outer, holes: holes, top, up: true, colour)
            cap(outer, holes: holes, base, up: false, colour)
        case "loft":
            guard let profile = s.profile?.filter({ $0.count == 2 }), profile.count >= 2 else { return }
            let rr: [P2]
            let c: P2
            if let own = ring() {
                rr = own
                c = Geometry.polygon(own + [own[0]]).centroid.xy
            } else if let r = s.radius, r > 0 {
                rr = circle(r).map { at + $0 }
                c = at
            } else { return }
            loft(rr, c, base, profile.map { ($0[0], $0[1]) }, colour)
        default:
            break
        }
    }
}
