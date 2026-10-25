import Foundation
import Geometry
import GLTF
import simd

/// Builds a landmark's stylized low-poly model from its recipe
/// (LandmarkRecipe): every mass a prism of its outline with its plinth,
/// cornice, windows and roof, then the features (colonnades, pediments,
/// statues, boxes, steps), each face a flat colour of the palette's
/// landmark colours. One look for every landmark, since the recipe only
/// chooses among these words. The model is a GLB in metres around the
/// landmark's centre (+Y up, -Z north), one material a colour, written as
/// `model.glb` in its folder, where the pipeline places it.
///
/// Faces are oriented by a hint of which way they look (outward), so a
/// recipe cannot turn one inside out. Nothing is below the ground.
public enum LandmarkGenerator {
    public static let roofShapes = ["flat", "gabled", "hipped", "pyramidal", "dome", "onion", "spire", "mansard"]
    public static let featureKinds = ["colonnade", "pediment", "statue", "box", "steps"]

    /// What is wrong with a recipe, one line each: nothing when it builds.
    public static func check(_ r: LandmarkRecipe, _ source: LandmarkSource) -> [String] {
        var out: [String] = []
        let colours = Set(Palette.landmark.map(\.0))
        func colour(_ c: String?, _ at: String) {
            if let c, !colours.contains(c) { out.append("\(at): colour \(c) is not one of \(colours.sorted().joined(separator: ", "))") }
        }
        for (i, m) in r.masses.enumerated() {
            let at = "masses[\(i)]" + (m.id.map { " (\($0))" } ?? "")
            if let o = m.outline, source.ring(o) == nil { out.append("\(at): outline \(o) is not one of the landmark's buildings") }
            if m.outline == nil, (m.polygon?.count ?? 0) < 3 { out.append("\(at): needs an outline or a polygon of 3 points at least") }
            if m.top <= m.base { out.append("\(at): top \(m.top) is not above base \(m.base)") }
            if m.base < 0 { out.append("\(at): base below the ground") }
            if let s = m.roof?.shape, !roofShapes.contains(s) { out.append("\(at): roof shape \(s) is not one of \(roofShapes.joined(separator: ", "))") }
            colour(m.colour, at)
            colour(m.roof?.colour, at + ".roof")
            colour(m.plinth?.colour, at + ".plinth")
            colour(m.cornice?.colour, at + ".cornice")
            colour(m.windows?.colour, at + ".windows")
            if let w = m.windows, w.storeys < 1 || w.spacing <= 0 { out.append("\(at).windows: storeys and spacing must be positive") }
        }
        for (i, f) in r.features.enumerated() {
            let at = "features[\(i)] (\(f.kind))"
            colour(f.colour, at)
            switch f.kind {
            case "colonnade", "pediment", "steps":
                if f.from?.count != 2 || f.to?.count != 2 { out.append("\(at): needs from and to, [x, y] each") }
                if (f.height ?? 0) <= 0 { out.append("\(at): needs a height") }
            case "statue":
                if f.at?.count != 2 { out.append("\(at): needs at, [x, y]") }
            case "box":
                if (f.polygon?.count ?? 0) < 3 { out.append("\(at): needs a polygon of 3 points at least") }
                if (f.top ?? 0) <= (f.base ?? 0) { out.append("\(at): top must be above base") }
            default:
                out.append("\(at): kind is not one of \(featureKinds.joined(separator: ", "))")
            }
        }
        return out
    }

    /// The model of a recipe: its triangles by colour.
    public static func build(_ r: LandmarkRecipe, _ source: LandmarkSource) -> Model {
        let m = Model()
        for mass in r.masses {
            let ring = mass.outline.flatMap { source.ring($0) } ?? (mass.polygon ?? []).filter { $0.count == 2 }.map { P2($0[0], $0[1]) }
            guard ring.count >= 3, mass.top > mass.base else { continue }
            m.mass(ccw(ring), mass)
        }
        for f in r.features { m.feature(f) }
        return m
    }

    /// Builds the recipe of a landmark's folder into its model.glb. Returns
    /// the problems found (nothing written when there are any) and what was
    /// built.
    public static func run(folder: URL) throws -> (problems: [String], summary: String) {
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        let url = folder.appendingPathComponent("recipe.json")
        let recipe = try LandmarkRecipe.read(url)
        let problems = check(recipe, source)
        guard problems.isEmpty else { return (problems, "") }
        let model = build(recipe, source)
        try model.write(folder.appendingPathComponent("model.glb"), name: source.name)
        return ([], model.summary)
    }

    // MARK: The model

    public final class Model {
        /// Triangles by colour name, three corners each, X east, Y north, Z up.
        var tris: [String: [V3]] = [:]

        public var triangles: Int { tris.values.reduce(0) { $0 + $1.count } / 3 }

        public var summary: String {
            let all = tris.values.flatMap { $0 }
            guard let first = all.first else { return "nothing built" }
            let lo = all.reduce(first) { simd_min($0, $1) }, hi = all.reduce(first) { simd_max($0, $1) }
            return String(format: "%d triangles, %.0f × %.0f m, %.1f m high, colours %@", triangles,
                          hi.x - lo.x, hi.y - lo.y, hi.z, tris.keys.sorted().joined(separator: " "))
        }

        public func write(_ url: URL, name: String) throws {
            let hex = Dictionary(uniqueKeysWithValues: Palette.landmark)
            let parts = tris.keys.sorted().map { c -> GLTF.Part in
                let (r, g, b) = Palette.rgb(hex[c] ?? "#FF00FF")
                return GLTF.Part(material: .init(name: c, factor: [Double(r) / 255, Double(g) / 255, Double(b) / 255, 1]),
                                 tris: tris[c]!, uvs: nil)
            }
            try GLTF.writeModel(url, parts, name: name)
        }

        // MARK: Faces

        /// A triangle turned to look along `hint`.
        func tri(_ a: V3, _ b: V3, _ c: V3, _ hint: V3, _ colour: String) {
            let n = simd_cross(b - a, c - a)
            guard simd_length(n) > 1e-9 else { return }
            tris[colour, default: []] += simd_dot(n, hint) >= 0 ? [a, b, c] : [a, c, b]
        }

        /// A convex planar polygon, fanned.
        func face(_ p: [V3], _ hint: V3, _ colour: String) {
            guard p.count >= 3 else { return }
            for i in 1..<(p.count - 1) { tri(p[0], p[i], p[i + 1], hint, colour) }
        }

        /// A polygon with holes, flat at `z`, looking up or down.
        func cap(_ ring: [P2], holes: [[P2]] = [], _ z: Double, up: Bool, _ colour: String) {
            let shape = Geometry.polygon(ring + [ring[0]], holes: holes.map { $0 + [$0[0]] })
            for t in shape.constrainedDelaunay() where t.count == 3 {
                tri(V3(t[0].x, t[0].y, z), V3(t[1].x, t[1].y, z), V3(t[2].x, t[2].y, z), V3(0, 0, up ? 1 : -1), colour)
            }
        }

        /// Walls of a ring from `z0` to `z1`, looking out (a counter-clockwise
        /// ring's right).
        func walls(_ ring: [P2], _ z0: Double, _ z1: Double, _ colour: String) {
            guard z1 > z0 else { return }
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                face([V3(a.x, a.y, z0), V3(b.x, b.y, z0), V3(b.x, b.y, z1), V3(a.x, a.y, z1)], outward(a, b), colour)
            }
        }

        func prism(_ ring: [P2], _ z0: Double, _ z1: Double, _ colour: String) {
            walls(ring, z0, z1, colour)
            cap(ring, z1, up: true, colour)
            if z0 > 0.01 { cap(ring, z0, up: false, colour) }
        }

        // MARK: A mass

        func mass(_ ring: [P2], _ m: LandmarkRecipe.Mass) {
            let plinth = m.plinth.map { min($0.height, (m.top - m.base) * 0.4) } ?? 0
            let cornice = m.cornice.map { min($0.height, (m.top - m.base) * 0.3) } ?? 0
            let lo = m.base + plinth, hi = m.top - cornice
            walls(ring, lo, hi, m.colour)
            if m.base > 0.01 { cap(ring, m.base, up: false, m.colour) }
            if let p = m.plinth, plinth > 0 {
                let out = grown(ring, p.depth ?? 0.15)
                walls(out, m.base, lo, p.colour ?? "lm_stone")
                cap(out, holes: [ring], lo, up: true, p.colour ?? "lm_stone")
                if m.base > 0.01 { cap(out, holes: [ring], m.base, up: false, p.colour ?? "lm_stone") }
            }
            if let c = m.cornice, cornice > 0 {
                let out = grown(ring, c.depth ?? 0.4)
                walls(out, hi, m.top, c.colour ?? "lm_white")
                cap(out, holes: [ring], hi, up: false, c.colour ?? "lm_white")
                cap(out, holes: [ring], m.top, up: true, c.colour ?? "lm_white")
            }
            if let w = m.windows { windows(ring, lo, hi, w, wall: m.colour) }
            roof(ring, m.top, m.roof)
        }

        /// Window panes standing a little proud of the walls, storey by
        /// storey, spaced along every wall long enough.
        func windows(_ ring: [P2], _ lo: Double, _ hi: Double, _ w: LandmarkRecipe.Windows, wall: String) {
            guard w.storeys >= 1, hi - lo > 1 else { return }
            let colour = w.colour ?? "lm_dark", storey = (hi - lo) / Double(w.storeys)
            let height = min(w.height, storey * 0.65), width = min(w.width, w.spacing * 0.7), proud = 0.08
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count], len = simd_length(b - a)
                let n = Int((len - 1) / w.spacing)
                guard n >= 1 else { continue }
                let d = (b - a) / len, o = outward(a, b), out2 = P2(o.x, o.y)
                for k in 0..<n {
                    let t = len / 2 + (Double(k) - Double(n - 1) / 2) * w.spacing
                    for s in 0..<w.storeys {
                        let zc = lo + storey * (Double(s) + 0.5), z0 = zc - height / 2
                        let z1 = z0 + height - (w.arched == true ? width / 2 : 0)
                        func p(_ u: Double, _ z: Double, _ off: Double) -> V3 {
                            let q = a + d * (t + u) + out2 * off
                            return V3(q.x, q.y, z)
                        }
                        let h = width / 2
                        face([p(-h, z0, proud), p(h, z0, proud), p(h, z1, proud), p(-h, z1, proud)], o, colour)
                        face([p(-h, z0, 0), p(h, z0, 0), p(h, z0, proud), p(-h, z0, proud)], V3(0, 0, -1), colour)
                        face([p(-h, z1, 0), p(h, z1, 0), p(h, z1, proud), p(-h, z1, proud)], V3(0, 0, 1), colour)
                        face([p(-h, z0, 0), p(-h, z1, 0), p(-h, z1, proud), p(-h, z0, proud)], V3(-d.x, -d.y, 0), colour)
                        face([p(h, z0, 0), p(h, z1, 0), p(h, z1, proud), p(h, z0, proud)], V3(d.x, d.y, 0), colour)
                        if w.arched == true {
                            let steps = 4
                            for j in 0..<steps {
                                let a0 = Double.pi * Double(j) / Double(steps), a1 = Double.pi * Double(j + 1) / Double(steps)
                                tri(p(0, z1, proud), p(h * cos(a0), z1 + h * sin(a0), proud),
                                    p(h * cos(a1), z1 + h * sin(a1), proud), o, colour)
                            }
                        }
                    }
                }
            }
        }

        // MARK: Roofs

        func roof(_ ring: [P2], _ top: Double, _ roof: LandmarkRecipe.Roof?) {
            guard let roof, roof.shape != "flat" else { return cap(ring, top, up: true, "lm_stone") }
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
            default:
                planes(ring, top, roof.shape, roof.height, colour)
            }
        }

        /// Rings of the outline drawn in toward its centre, each `(scale,
        /// rise)`, joined by faces: a dome, an onion, a spire. A last scale of
        /// 0 is a point, else the top is capped flat.
        func loft(_ ring: [P2], _ c: P2, _ top: Double, _ profile: [(Double, Double)], _ colour: String) {
            func at(_ p: P2, _ k: Int) -> V3 { let q = c + (p - c) * profile[k].0; return V3(q.x, q.y, top + profile[k].1) }
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

        /// A gabled, hipped or mansard roof over the outline's smallest
        /// rectangle: planes rising from its sides, each clipped to the
        /// outline, with gable walls where the roof rises over the outline's
        /// edge.
        func planes(_ ring: [P2], _ top: Double, _ shape: String, _ height: Double?, _ colour: String) {
            let outline = Geometry.polygon(ring + [ring[0]])
            let rect = Array(outline.minimumRotatedRectangle.exterior.dropLast())
            guard rect.count == 4 else { return cap(ring, top, up: true, colour) }
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
            for region in regions {
                let poly = region.poly.map(world)
                guard abs(signedArea(poly)) > 1e-6 else { continue }
                let clipped = outline.intersection(Geometry.polygon(poly + [poly[0]]))
                func z(_ p: P2) -> Double { top + h * max(0, min(1, region.rise(local(p)))) }
                for part in clipped.polygons {
                    for t in part.constrainedDelaunay() where t.count == 3 {
                        tri(V3(t[0].x, t[0].y, z(t[0])), V3(t[1].x, t[1].y, z(t[1])), V3(t[2].x, t[2].y, z(t[2])), V3(0, 0, 1), colour)
                    }
                    // Gable walls: the outline's own edges under a rising roof.
                    let r = Array(part.exterior.dropLast())
                    for i in r.indices {
                        let a = r[i], b = r[(i + 1) % r.count]
                        guard edge.distance(.point((a + b) / 2)) < 1e-4, z(a) > top + 1e-3 || z(b) > top + 1e-3 else { continue }
                        let o = outwardOf(outline, a, b)
                        face([V3(a.x, a.y, top), V3(b.x, b.y, top), V3(b.x, b.y, z(b)), V3(a.x, a.y, z(a))], o, "lm_cream")
                    }
                }
            }
        }

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
                    walls(ring, base, base + height - beam, colour)
                    if base > 0.01 { cap(ring, base, up: false, colour) }
                }
                let side = P2(-d.y, d.x) * (r + 0.3), along = d * (r + 0.3)
                prism(ccw([a - along - side, b + along - side, b + along + side, a - along + side]), base + height - beam, base + height, colour)
            case "pediment":
                guard let a = p2(f.from), let b = p2(f.to), let height = f.height, height > 0 else { return }
                let len = simd_length(b - a), d = (b - a) / max(len, 1e-9), n = P2(d.y, -d.x) * (f.depth ?? 1.5)
                let m = (a + b) / 2
                func v(_ p: P2, _ z: Double) -> V3 { V3(p.x, p.y, z) }
                let up = V3(0, 0, 1), dir = V3(d.x, d.y, 0), right = V3(n.x, n.y, 0)
                face([v(a + n, base), v(b + n, base), v(m + n, base + height)], right, colour)
                face([v(a, base), v(b, base), v(m, base + height)], -right, colour)
                face([v(a, base), v(a + n, base), v(m + n, base + height), v(m, base + height)], up - dir, colour)
                face([v(m, base + height), v(m + n, base + height), v(b + n, base), v(b, base)], up + dir, colour)
                if base > 0.01 { face([v(a, base), v(b, base), v(b + n, base), v(a + n, base)], -up, colour) }
            case "statue":
                guard let at = p2(f.at) else { return }
                let w = (f.width ?? 2) / 2, h = f.height ?? 4
                let ring = (0..<8).map { k -> P2 in let t = Double(k) / 8 * 2 * .pi; return at + P2(cos(t), sin(t)) * w }
                if base > 0.01 { cap(ring, base, up: false, colour) }
                loft(ring, at, base, [(1, 0), (0.7, 0.15 * h), (0.55, 0.7 * h), (0.3, 0.76 * h), (0.38, 0.88 * h), (0, h)], colour)
            case "box":
                let ring = (f.polygon ?? []).compactMap(p2)
                guard ring.count >= 3, let top = f.top, top > base else { return }
                prism(ccw(ring), base, top, colour)
            case "steps":
                guard let a = p2(f.from), let b = p2(f.to), let height = f.height, height > 0 else { return }
                let len = simd_length(b - a), d = (b - a) / max(len, 1e-9), n = P2(d.y, -d.x)
                let count = max(1, f.count ?? Int(height / 0.16)), depth = f.depth ?? Double(count) * 0.35
                // The profile across, from the line (top) out to the ground.
                var profile: [P2] = [P2(0, 0), P2(0, height)]
                for i in 0..<count {
                    let o = depth * Double(i + 1) / Double(count), z = height * Double(count - i - 1) / Double(count)
                    profile += [P2(o, height * Double(count - i) / Double(count)), P2(o, z)]
                }
                profile = profile.reduce(into: [P2]()) { out, p in if out.last.map({ simd_length($0 - p) > 1e-9 }) ?? true { out.append(p) } }
                if simd_length(profile.last! - profile[0]) < 1e-9 { profile.removeLast() }
                func v(_ q: P2, _ t: Double) -> V3 { let p = a + d * t + n * q.x; return V3(p.x, p.y, base + q.y) }
                let mid = profile.reduce(P2.zero, +) / Double(profile.count)
                for i in profile.indices {
                    let p = profile[i], q = profile[(i + 1) % profile.count]
                    let e = q - p, out = P2(e.y, -e.x)
                    let hint2 = simd_dot(out, (p + q) / 2 - mid) >= 0 ? out : -out
                    face([v(p, 0), v(q, 0), v(q, len), v(p, len)], V3(n.x * hint2.x, n.y * hint2.x, hint2.y), colour)
                }
                let shape = Geometry.polygon(profile + [profile[0]])
                for t in shape.constrainedDelaunay() where t.count == 3 {
                    tri(v(t[0], 0), v(t[1], 0), v(t[2], 0), V3(-d.x, -d.y, 0), colour)
                    tri(v(t[0], len), v(t[1], len), v(t[2], len), V3(d.x, d.y, 0), colour)
                }
            default:
                break
            }
        }
    }

    // MARK: Plan helpers

    static func ccw(_ ring: [P2]) -> [P2] {
        var r = ring
        if r.count > 1, simd_length(r[0] - r[r.count - 1]) < 1e-9 { r.removeLast() }
        return signedArea(r) < 0 ? r.reversed() : r
    }

    /// A counter-clockwise ring grown outward by `d`, square at its corners.
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

private extension LandmarkGenerator.Model {
    func outward(_ a: P2, _ b: P2) -> V3 { LandmarkGenerator.outward(a, b) }
    func grown(_ ring: [P2], _ d: Double) -> [P2] { LandmarkGenerator.grown(ring, d) }
    func ccw(_ ring: [P2]) -> [P2] { LandmarkGenerator.ccw(ring) }
    func outwardOf(_ o: Geometry, _ a: P2, _ b: P2) -> V3 { LandmarkGenerator.outwardOf(o, a, b) }
}
