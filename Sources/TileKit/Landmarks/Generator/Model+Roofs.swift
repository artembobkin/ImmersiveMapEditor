import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// A mass's roof: flat, vaulted, hipped or mansard from every edge of
/// its outline, a loft of a profile (domes, cones, onions), and gabled or
/// skillion planes over the outline's smallest rectangle.
extension LandmarkGenerator.Model {
    // MARK: Roofs

    /// The roof over a mass: flat (with a parapet when asked), a loft
    /// (dome, onion, spire, pyramid), or planes with eaves reaching
    /// `overhang` beyond the walls, a fascia under them and a soffit back
    /// to `under` (the cornice's outer ring, or the wall).
    func roof(_ ring: [P2], _ top: Double, _ roof: LandmarkRecipe.Roof?, wall: String) {
        guard let roof, roof.shape != "flat" else {
            // The body's own ceiling is the flat roof; a parapet is a band
            // on it, always (the toy's edge), its top a light rim that
            // outlines the building from above.
            let p = max(roof?.parapet ?? 0, Caricature.parapet)
            let colour = wall
            let inner = grown(ring, -0.45)
            if inner.count >= 3, inner != ring {
                band(inner, ring, top, top + p, colour, top: "rim")
            } else {
                prism(ring, top, top + p, colour)
            }
            return
        }
        let colour = roof.colour ?? "lm_green"
        let c = Geometry.polygon(ring + [ring[0]]).centroid.xy
        let r = ring.map { simd_length($0 - c) }.reduce(0, +) / Double(ring.count)
        switch roof.shape {
        case "dome":
            let h = roof.height ?? r
            loft(ring, c, top, (0...5).map { k in let a = Double.pi / 2 * Double(k) / 5; return (cos(a), h * sin(a)) }, colour)
        case "onion":
            let h = roof.height ?? r * 2.2
            loft(ring, c, top, [(1, 0), (1.25, 0.22), (1.2, 0.42), (0.85, 0.6), (0.45, 0.76), (0.15, 0.9), (0, 1)].map { ($0.0, $0.1 * h) }, colour)
        case "spire":
            loft(ring, c, top, [(1, 0), (0, roof.height ?? r * 4)], colour)
        case "pyramidal":
            loft(ring, c, top, [(1, 0), (0, roof.height ?? r * 0.8)], colour)
        case "vault":
            vault(ring, top, roof.height, colour)
        case "gabled", "skillion":
            // The roof a closed solid: its slopes and gables over a flat
            // underside, with a fascia around the eaves when they overhang.
            begin()
            let over = (roof.overhang ?? 0.6) > 0.05 ? max(roof.overhang ?? 0.6, Caricature.eaves) : 0
            guard over > 0.05 else { return planes(ring, top, roof.shape, roof.height, colour, wall: wall, bottom: top) }
            let eave = grown(ring, over), fascia = Caricature.fascia
            planes(eave, top + fascia, roof.shape, roof.height, colour, wall: wall, bottom: top)
        default:
            // Hipped and mansard: every edge of the outline an eave, the
            // slopes rising inward from all of them.
            let over = (roof.overhang ?? 0.6) > 0.05 ? max(roof.overhang ?? 0.6, Caricature.eaves) : 0
            let eave = over > 0.05 ? grown(ring, over) : ring
            let fascia = over > 0.05 ? Caricature.fascia : 0
            hipped(eave, top + fascia, roof.height, mansard: roof.shape == "mansard", colour, bottom: top)
        }
    }

    /// A barrel vault along the outline's long side: a half-ellipse
    /// across its smallest rectangle, `height` high (half its width
    /// unless given), from end to end, one closed solid on the flat
    /// underside. In a glass colour a glazed vault with its ribs: an arch
    /// of the frame's colour every `Caricature.vaultRibStep` and at both
    /// ends, and a rail along the crown and along both eaves (the user,
    /// 2026-11-03: GUM's galleries as gabled planes of glass read as
    /// plain blue slabs).
    func vault(_ ring: [P2], _ top: Double, _ height: Double?, _ colour: String) {
        let rect = Array(Geometry.polygon(ring + [ring[0]]).minimumRotatedRectangle.exterior.dropLast())
        guard rect.count == 4 else { return cap(ring, top, up: true, colour) }
        let c = rect.reduce(P2.zero, +) / 4
        var u = rect[1] - rect[0], v = rect[2] - rect[1]
        if simd_length(u) < simd_length(v) { swap(&u, &v) }
        let hl = simd_length(u) / 2, hw = simd_length(v) / 2
        u /= hl * 2
        v /= hw * 2
        let h = max(0.5, height ?? hw), n = 12
        // The profile at `x` along the vault: from one eave over the crown
        // to the other, the ring closed by the flat underside.
        func profile(_ x: Double) -> [V3] {
            (0...n).map { k in
                let a = Double.pi * Double(k) / Double(n), p = c + u * x + v * (hw * cos(a))
                return V3(p.x, p.y, top + h * sin(a))
            }
        }
        sweep([profile(-hl), profile(hl)], colour)
        guard LandmarkRecipe.glassColours.contains(colour) else { return }
        let frame = "lm_dark", r = Caricature.vaultRib
        let count = max(1, Int((2 * hl / Caricature.vaultRibStep).rounded()))
        for k in 0...count {
            let arc = profile(-hl + 2 * hl * Double(k) / Double(count))
            for j in 0..<n { tube(arc[j], arc[j + 1], r, r, segments: 6, frame) }
        }
        for a in [0.0, Double.pi / 2, Double.pi] {
            let p0 = c - u * hl + v * (hw * cos(a)), p1 = c + u * hl + v * (hw * cos(a))
            tube(V3(p0.x, p0.y, top + h * sin(a)), V3(p1.x, p1.y, top + h * sin(a)), r, r, segments: 6, frame)
        }
    }

    /// A hipped or mansard roof over any outline (the user, 2026-11-01:
    /// over an L-shaped or a skewed outline the planes of the smallest
    /// rectangle, cut by the outline, left walls in the facade's colour
    /// standing over the cornice): every edge of the ring is an eave,
    /// and the roof rises inward at one slope from all of them, as a
    /// roof framed on the plan does. The slopes are the ring drawn in
    /// to its inset (`buffer` with mitred corners), the band between
    /// triangulated: its creases follow the ring's corners inward, the
    /// hips and valleys of the real roof. A hipped roof's inset is as
    /// deep as the outline allows, the ridge where it closes; a mansard's
    /// is shallow and steep, with a flat top. One closed solid: the
    /// slopes, the flat tops, the underside and a fascia around the eaves.
    func hipped(_ ring: [P2], _ top: Double, _ height: Double?, mansard: Bool, _ colour: String, bottom: Double) {
        let outer = Geometry.polygon(ring + [ring[0]])
        func inset(_ d: Double) -> [[P2]] {
            outer.buffer(-d, quadSegs: 1, join: .mitre).polygons.filter { $0.area > 0.05 }.map { ccw(Array($0.exterior.dropLast())) }
        }
        // The deepest inset the outline allows, by halving.
        var lo = 0.0, hi = max(1.0, ring.map { simd_length($0 - ring[0]) }.max() ?? 1)
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            if inset(mid).isEmpty { hi = mid } else { lo = mid }
        }
        let deepest = lo
        guard deepest > 0.3 else {
            return planes(ring, top, "hipped", height, colour, wall: colour, bottom: bottom)
        }
        let h = height ?? deepest * (mansard ? 1.2 : 0.7)
        let d = mansard ? min(deepest * 0.9, max(0.5, min(deepest * 0.35, h * 0.4))) : deepest * 0.92
        let inner = inset(d)
        guard !inner.isEmpty else {
            return planes(ring, top, "hipped", height, colour, wall: colour, bottom: bottom)
        }
        begin()
        let edge = outer.boundary
        func z(_ p: P2) -> Double { top + h * max(0, min(1, edge.distance(.point(p)) / d)) }
        // The slopes: the band from the eaves in to the inset.
        let band = Geometry.polygon(ring + [ring[0]], holes: inner.map { $0 + [$0[0]] })
        for t in band.constrainedDelaunay() where t.count == 3 {
            tri(V3(t[0].x, t[0].y, z(t[0])), V3(t[1].x, t[1].y, z(t[1])), V3(t[2].x, t[2].y, z(t[2])), V3(0, 0, 1), colour)
        }
        for r in inner { cap(r, top + h, up: true, colour) }
        cap(ring, bottom, up: false, colour)
        // The fascia: the eaves' edge from the underside up to the slope.
        if top > bottom + 1e-6 {
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                face([V3(a.x, a.y, bottom), V3(b.x, b.y, bottom), V3(b.x, b.y, top), V3(a.x, a.y, top)], outward(a, b), colour)
            }
        }
    }

    /// Rings of the outline drawn in toward its centre, each `(scale,
    /// rise)`, joined by faces: a dome, an onion, a spire. A last scale of
    /// 0 is a point, else the top is capped flat.
    func loft(_ ring: [P2], _ c: P2, _ top: Double, _ profile: [(Double, Double)], _ colour: String) {
        func at(_ p: P2, _ k: Int) -> V3 { let q = c + (p - c) * profile[k].0; return V3(q.x, q.y, top + profile[k].1) }
        begin()
        if profile[0].0 > 1e-6 { cap(ring.map { c + ($0 - c) * profile[0].0 }, top + profile[0].1, up: false, colour) }
        for k in 0..<(profile.count - 1) {
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let hint = outward(a, b) * 1 + V3(0, 0, profile[k + 1].0 < profile[k].0 ? 0.2 : -0.2)
                face([at(a, k), at(b, k), at(b, k + 1), at(a, k + 1)].reduce(into: [V3]()) { out, p in
                    if out.last.map({ simd_length($0 - p) > 1e-6 }) ?? true { out.append(p) }
                }, hint, colour)
            }
        }
        if let last = profile.last, last.0 > 1e-6 {
            cap(ring.map { c + ($0 - c) * last.0 }, top + last.1, up: true, colour)
        }
    }

    /// A gabled, skillion, hipped or mansard roof over the outline's smallest
    /// rectangle: planes rising from its sides, each clipped to the
    /// outline, with gable walls where the roof rises over the outline's
    /// edge.
    /// A roof of planes as one closed solid: over every region its
    /// slope, under it the flat underside at `bottom`, and on the
    /// outline's edges the walls from `bottom` up to the slope (the
    /// fascia under the eaves, the gables), all cut from the same pieces
    /// so their edges meet.
    func planes(_ ring: [P2], _ top: Double, _ shape: String, _ height: Double?, _ colour: String, wall: String, bottom: Double) {
        let outline = Geometry.polygon(ring + [ring[0]])
        let rect = Array(outline.minimumRotatedRectangle.exterior.dropLast())
        guard rect.count == 4 else {
            cap(ring, top, up: true, colour)
            cap(ring, bottom, up: false, colour)
            if top > bottom + 1e-6 { walls(ring, bottom, top, colour) }
            return
        }
        let c = rect.reduce(P2.zero, +) / 4
        var u = rect[1] - rect[0], v = rect[2] - rect[1]
        if simd_length(u) < simd_length(v) { swap(&u, &v) }
        let hl = simd_length(u) / 2, hw = simd_length(v) / 2
        u /= hl * 2
        v /= hw * 2
        let h = height ?? hw * (shape == "mansard" ? 0.9 : 0.7)
        // Each plane: its region in (along, across) and its rise from 0 to 1.
        typealias Region = (poly: [P2], rise: (P2) -> Double)
        let big = 1.001
        var regions: [Region] = []
        switch shape {
        case "skillion":
            regions = [([P2(-hl, -hw), P2(hl, -hw), P2(hl, hw), P2(-hl, hw)], { (hw - $0.y) / (2 * hw) })]
        case "gabled":
            regions = [([P2(-hl, 0), P2(hl, 0), P2(hl, hw), P2(-hl, hw)], { (hw - abs($0.y)) / hw }),
                       ([P2(-hl, -hw), P2(hl, -hw), P2(hl, 0), P2(-hl, 0)], { (hw - abs($0.y)) / hw })]
        default:
            let s = shape == "mansard" ? min(hw * 0.35, h * 0.4) : hw
            regions = [([P2(-hl, hw), P2(-hl + s, hw - s), P2(hl - s, hw - s), P2(hl, hw)], { (hw - $0.y) / s }),
                       ([P2(-hl, -hw), P2(hl, -hw), P2(hl - s, -hw + s), P2(-hl + s, -hw + s)], { (hw + $0.y) / s }),
                       ([P2(hl, -hw), P2(hl, hw), P2(hl - s, hw - s), P2(hl - s, -hw + s)], { (hl - $0.x) / s }),
                       ([P2(-hl, -hw), P2(-hl + s, -hw + s), P2(-hl + s, hw - s), P2(-hl, hw)], { (hl + $0.x) / s })]
            if s < hw - 1e-6 {
                regions.append(([P2(-hl + s, -hw + s), P2(hl - s, -hw + s), P2(hl - s, hw - s), P2(-hl + s, hw - s)], { _ in 1 }))
            }
        }
        func world(_ q: P2) -> P2 { c + u * q.x * big + v * q.y * big }
        func local(_ p: P2) -> P2 { P2(simd_dot(p - c, u), simd_dot(p - c, v)) }
        let edge = outline.boundary
        // Every clipped slope a closed solid of its own: its slope on
        // top, the flat underside, and a wall on each of its edges from
        // the underside up to the slope (a fascia under the eaves, a
        // gable where the roof rises over the outline's edge, and on an
        // edge shared with the next slope a face the union removes, as
        // the two slopes' faces coincide there). One solid for the whole
        // roof was not closed where the clipped slopes' edges met.
        for region in regions {
            let poly = region.poly.map(world)
            guard abs(signedArea(poly)) > 1e-6 else { continue }
            let clipped = outline.intersection(Geometry.polygon(poly + [poly[0]]))
            func z(_ p: P2) -> Double { top + h * max(0, min(1, region.rise(local(p)))) }
            for part in clipped.polygons {
                let r = ccw(Array(part.exterior.dropLast()))
                guard r.count >= 3, abs(signedArea(r)) > 0.01 else { continue }
                begin()
                let shape = Geometry.polygon(r + [r[0]])
                for t in shape.constrainedDelaunay() where t.count == 3 {
                    tri(V3(t[0].x, t[0].y, z(t[0])), V3(t[1].x, t[1].y, z(t[1])), V3(t[2].x, t[2].y, z(t[2])), V3(0, 0, 1), colour)
                    tri(V3(t[0].x, t[0].y, bottom), V3(t[1].x, t[1].y, bottom), V3(t[2].x, t[2].y, bottom), V3(0, 0, -1), colour)
                }
                for i in r.indices {
                    let a = r[i], b = r[(i + 1) % r.count]
                    guard z(a) > bottom + 1e-6 || z(b) > bottom + 1e-6 else { continue }
                    let o = outward(a, b)
                    let onEdge = edge.distance(.point((a + b) / 2)) < 1e-4
                    let gable = onEdge && (z(a) > top + 1e-3 || z(b) > top + 1e-3)
                    face([V3(a.x, a.y, bottom), V3(b.x, b.y, bottom), V3(b.x, b.y, z(b)), V3(a.x, a.y, z(a))].reduce(into: [V3]()) { out, p in
                        if out.last.map({ simd_length($0 - p) > 1e-9 }) ?? true { out.append(p) }
                    }, o, gable ? wall : colour)
                }
            }
        }
    }
}
