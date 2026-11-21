import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// A mass of a recipe built: its walls from the plinth to its top, its
/// bands (plinth, string courses, cornice) and its roof.
extension LandmarkGenerator.Model {
    // MARK: A mass

    /// A mass: its body a closed solid from base to top (the walls with
    /// their openings, plain strips behind the plinth and the cornice,
    /// a floor and a ceiling), then the bands, pilasters and roof as
    /// closed solids of their own, for the union to join.
    func mass(_ ring: [P2], _ m: LandmarkRecipe.Mass) {
        let plinth = m.plinth.map { min(max($0.height, Caricature.plinthHeight), (m.top - m.base) * 0.4) } ?? 0
        let cornice = m.cornice.map { min(max($0.height, Caricature.corniceHeight), (m.top - m.base) * 0.3) } ?? 0
        let lo = m.base + plinth, hi = m.top - cornice
        let doors = place(m.doors ?? [], on: ring)
        begin()
        // The wall from the mass's foot, its doors cut from the ground
        // through the plinth, its windows laid from the plinth's top.
        let cuts = walls(ring, m.base, hi, m.colour, windows: m.windows, doors: doors, windowsFrom: lo)
        if cornice > 0 { walls(ring, hi, m.top, m.colour) }
        cap(ring, m.base, up: false, m.colour)
        let flat = m.roof == nil || m.roof?.shape == "flat"
        cap(ring, m.top, up: true, flat ? (m.roof?.colour ?? "lm_roof") : m.colour)
        // The plinth, broken where a door goes through it.
        if let p = m.plinth, plinth > 0 { band(ring, grown(ring, max(p.depth ?? 0.15, Caricature.proud)), m.base, lo, p.colour ?? "lm_stone", cuts: cuts) }
        if let c = m.cornice, cornice > 0 {
            // A profile of steps up and out, not one block (the user,
            // 2026-11-01): a bed moulding, a corona, a cymatium.
            let depth = max(c.depth ?? 0.4, Caricature.corniceDepth)
            var z = hi
            for step in Caricature.corniceSteps {
                let z1 = min(m.top, z + cornice * step.height)
                band(ring, grown(ring, depth * step.depth), z, z1, c.colour ?? "lm_white")
                z = z1
            }
        }
        if LandmarkRecipe.glassColours.contains(m.colour) {
            glazing(ring, lo, hi, storey: m.windows.map { max(2, (hi - lo) / Double($0.storeys)) } ?? Caricature.glazingStorey,
                    spacing: m.mullions, frame: m.frame)
        }
        if let p = m.pilasters { pilasters(ring, lo, hi, p, cuts: cuts, wall: m.colour) }
        if let b = m.bands, let w = m.windows, w.storeys >= 2 {
            let storey = (hi - lo) / Double(w.storeys), out = grown(ring, max(b.depth ?? 0.15, Caricature.proud))
            let height = max(b.height, Caricature.bandHeight)
            for k in 1..<w.storeys {
                let z = lo + storey * Double(k) - height / 2
                band(ring, out, z, z + height, b.colour ?? "lm_white", cuts: cuts)
            }
        }
        roof(ring, m.top, m.roof, wall: m.colour)
    }

    /// A closed ring of material around a body, from `inner` out to
    /// `outer`, `z0` to `z1`: a plinth, a cornice, a string course.
    func band(_ inner: [P2], _ outer: [P2], _ z0: Double, _ z1: Double, _ colour: String, cuts: [Cut] = [], top: String? = nil) {
        // Cut around the openings it would cross: the band in pieces, one
        // a wall between its openings (each a closed prism), a piece at a
        // wall's end reaching `depth` past the corner so the pieces of
        // two walls overlap there and the union joins them (the outer
        // ring's corners are not relied on: its buffer starts it where
        // it likes, and a piece drawn to them was a twisted solid).
        let crossing = cuts.filter { $0.z1 > z0 && $0.z0 < z1 }
        if !crossing.isEmpty {
            let depth = Geometry.polygon(outer + [outer[0]]).boundary.distance(.point(inner[0]))
            guard depth > 0.02 else { return }
            for i in inner.indices {
                let a = inner[i], b = inner[(i + 1) % inner.count], len = simd_length(b - a)
                guard len > 1e-6 else { continue }
                let d = (b - a) / len, o = outward(a, b), o2 = P2(o.x, o.y)
                let spans = crossing.filter { $0.edge == i }.map { (max(0, $0.t0 - 0.25), min(len, $0.t1 + 0.25)) }.sorted { $0.0 < $1.0 }
                var from = 0.0
                var pieces: [(Double, Double)] = []
                for sp in spans {
                    if sp.0 - from > 0.05 { pieces.append((from, sp.0)) }
                    from = max(from, sp.1)
                }
                if len - from > 0.05 { pieces.append((from, len)) }
                for (t0, t1) in pieces {
                    let s0 = t0 < 1e-6 ? -depth : t0, s1 = t1 > len - 1e-6 ? len + depth : t1
                    let p0 = a + d * s0, p1 = a + d * s1
                    prism(ccw([p0, p1, p1 + o2 * depth, p0 + o2 * depth]), z0, z1, colour)
                }
            }
            return
        }
        begin()
        walls(outer, z0, z1, colour)
        walls(inner.reversed(), z0, z1, colour)
        cap(outer, holes: [inner], z1, up: true, top ?? colour)
        cap(outer, holes: [inner], z0, up: false, colour)
    }
}
