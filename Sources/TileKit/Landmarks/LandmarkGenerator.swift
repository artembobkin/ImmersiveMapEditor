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
    public static let roofShapes = ["flat", "gabled", "skillion", "hipped", "pyramidal", "dome", "onion", "spire", "mansard"]

    /// OSM's roof:shape in the recipe's words: the nearest of its shapes,
    /// flat for one it has no likeness of.
    public static func roofShape(osm: String) -> String {
        if roofShapes.contains(osm) { return osm }
        switch osm {
        case "half-hipped", "side_hipped", "hip": return "hipped"
        case "gambrel", "round": return "mansard"
        case "saltbox", "side_half-hipped": return "gabled"
        case "lean_to", "shed": return "skillion"
        case "cone", "conical": return "spire"
        case "pyramid", "pyramidal": return "pyramidal"
        case "onion", "helm", "bulbous": return "onion"
        case "dome", "half_dome", "spherical": return "dome"
        default: return "flat"
        }
    }
    public static let featureKinds = ["colonnade", "pediment", "statue", "box", "steps"]
    public static let statueShapes = ["figure", "horse", "quadriga", "equestrian", "obelisk", "cross", "star"]
    public static let shapeKinds = ["box", "cylinder", "cone", "sphere", "dome", "prism", "loft"]
    /// How deep a window is cut into its wall.
    static let windowDepth = 0.25

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
        for (i, s) in r.shapes.enumerated() {
            let at = "shapes[\(i)] (\(s.kind))"
            colour(s.colour, at)
            let ring = (s.polygon?.count ?? 0) >= 3 || (s.outline.map { source.ring($0) != nil } ?? false)
            if let o = s.outline, source.ring(o) == nil { out.append("\(at): outline \(o) is not one of the landmark's buildings") }
            switch s.kind {
            case "box":
                if s.at?.count != 2 { out.append("\(at): needs at, [x, y]") }
                if s.size?.count != 3 || s.size!.contains(where: { $0 <= 0 }) { out.append("\(at): needs size, [along, across, up], positive") }
            case "cylinder", "cone":
                if s.at?.count != 2 { out.append("\(at): needs at, [x, y]") }
                if (s.radius ?? 0) <= 0 || (s.height ?? 0) <= 0 { out.append("\(at): needs a radius and a height") }
            case "sphere", "dome":
                if s.at?.count != 2 { out.append("\(at): needs at, [x, y]") }
                if (s.radius ?? 0) <= 0 { out.append("\(at): needs a radius") }
            case "prism":
                if !ring { out.append("\(at): needs a polygon of 3 points at least, or an outline") }
                if (s.top ?? 0) <= (s.base ?? 0) { out.append("\(at): top must be above base") }
            case "loft":
                if !ring && (s.radius ?? 0) <= 0 { out.append("\(at): needs a polygon, an outline or a radius") }
                if (s.radius ?? 0) > 0 && s.at?.count != 2 && !ring { out.append("\(at): a round loft needs at, [x, y]") }
                if (s.profile?.count ?? 0) < 2 || s.profile!.contains(where: { $0.count != 2 || $0[0] < 0 }) { out.append("\(at): needs a profile of 2 [scale, rise] pairs at least") }
            default:
                out.append("\(at): kind is not one of \(shapeKinds.joined(separator: ", "))")
            }
            if (s.base ?? 0) < 0 { out.append("\(at): base below the ground") }
            if let r = s.repeat, r.count < 1 || r.step.count != 3 { out.append("\(at).repeat: needs a count and a step [east, north, up]") }
            if let a = s.around, a.count < 1 || a.centre.count != 2 { out.append("\(at).around: needs a count and a centre [x, y]") }
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
                if let shape = f.shape, !statueShapes.contains(shape) { out.append("\(at): shape \(shape) is not one of \(statueShapes.joined(separator: ", "))") }
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
        for s in r.shapes { m.shape(s, source) }
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
            let parts = tris.keys.sorted().map { c -> GLTF.Part in
                let (r, g, b) = Palette.rgb(Palette.hex(c) ?? "#FF00FF")
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
        /// ring's right), with their windows cut in: a recess of windowDepth,
        /// reveals a tone darker than the wall, the glass darker still, the
        /// sill light, as an ordinary building's.
        func walls(_ ring: [P2], _ z0: Double, _ z1: Double, _ colour: String, windows: LandmarkRecipe.Windows? = nil) {
            guard z1 > z0 else { return }
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count], len = simd_length(b - a)
                guard len > 1e-6 else { continue }
                let d = (b - a) / len, o = outward(a, b), o2 = P2(o.x, o.y)
                // A point of the wall: along it, up, and in from its face.
                func p(_ t: Double, _ z: Double, _ depth: Double = 0) -> V3 {
                    let q = a + d * t - o2 * depth
                    return V3(q.x, q.y, z)
                }
                let holes = windows.map { openings(len, z0, z1, $0) } ?? []
                guard !holes.isEmpty else {
                    face([p(0, z0), p(len, z0), p(len, z1), p(0, z1)], o, colour)
                    continue
                }
                let shape = Geometry.polygon([P2(0, z0), P2(len, z0), P2(len, z1), P2(0, z1), P2(0, z0)],
                                             holes: holes.map { $0 + [$0[0]] })
                for t in shape.constrainedDelaunay() where t.count == 3 {
                    tri(p(t[0].x, t[0].y), p(t[1].x, t[1].y), p(t[2].x, t[2].y), o, colour)
                }
                for hole in holes {
                    let c = hole.reduce(P2.zero, +) / Double(hole.count)
                    for k in hole.indices {
                        let e0 = hole[k], e1 = hole[(k + 1) % hole.count]
                        let sill = abs(e0.y - e1.y) < 1e-9 && e0.y < c.y
                        let dir = c - (e0 + e1) / 2
                        face([p(e0.x, e0.y), p(e1.x, e1.y), p(e1.x, e1.y, LandmarkGenerator.windowDepth), p(e0.x, e0.y, LandmarkGenerator.windowDepth)],
                             V3(d.x * dir.x, d.y * dir.x, dir.y), sill ? "rim" : "\(colour).reveal")
                    }
                    face(hole.map { p($0.x, $0.y, LandmarkGenerator.windowDepth) }, o, "\(colour).glass")
                }
            }
        }

        /// The openings of a wall `len` long from `lo` to `hi`, in (along,
        /// up): a row a storey, spaced along the wall, never at its ends, an
        /// arched one topped by a half circle.
        func openings(_ len: Double, _ lo: Double, _ hi: Double, _ w: LandmarkRecipe.Windows) -> [[P2]] {
            guard w.storeys >= 1, hi - lo > 1, w.spacing > 0 else { return [] }
            let storey = (hi - lo) / Double(w.storeys)
            let height = min(w.height, storey * 0.65), width = min(w.width, w.spacing * 0.7), h = width / 2
            let n = Int((len - 1) / w.spacing)
            guard n >= 1, height > 0.3 else { return [] }
            var out: [[P2]] = []
            for k in 0..<n {
                let t = len / 2 + (Double(k) - Double(n - 1) / 2) * w.spacing
                for s in 0..<w.storeys {
                    let zc = lo + storey * (Double(s) + 0.5), zb = zc - height / 2
                    if w.arched == true, height > width {
                        let zt = zb + height - h
                        var ring = [P2(t - h, zb), P2(t + h, zb), P2(t + h, zt)]
                        for j in 1..<6 {
                            let a = Double.pi * Double(j) / 6
                            ring.append(P2(t + h * cos(a), zt + h * sin(a)))
                        }
                        out.append(ring + [P2(t - h, zt)])
                    } else {
                        out.append([P2(t - h, zb), P2(t + h, zb), P2(t + h, zb + height), P2(t - h, zb + height)])
                    }
                }
            }
            return out
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
            walls(ring, lo, hi, m.colour, windows: m.windows)
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
            roof(ring, m.top, m.roof)
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

        /// A gabled, skillion, hipped or mansard roof over the outline's smallest
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
                let h = f.height ?? 4, w = f.width ?? h * 0.6
                let heading = (f.heading ?? 180) * .pi / 180
                // Facing, and its left.
                let u = P2(sin(heading), cos(heading)), v = P2(-u.y, u.x)
                var z = base
                if let pedestal = f.pedestal, pedestal > 0 {
                    box(at, u, v, w, w, z, z + pedestal, colour)
                    z += pedestal
                }
                sculpture(f.shape ?? "figure", at, u, v, z, h, w, colour)
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

        // MARK: Shapes

        /// A shape's local frame: its origin at its place on its base, U
        /// along its heading, V to the left, W up, tipped by its pitch.
        struct Frame {
            let o, U, V, W: V3
            func p(_ a: Double, _ b: Double, _ c: Double) -> V3 { o + U * a + V * b + W * c }
            func dir(_ a: Double, _ b: Double, _ c: Double) -> V3 { U * a + V * b + W * c }
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

        func one(_ s: LandmarkRecipe.Shape, _ source: LandmarkSource, at: P2, heading: Double, base: Double) {
            let colour = s.colour ?? "lm_stone", n = max(3, min(64, s.segments ?? 16))
            let f = frame(at, base, heading, s.pitch ?? 0)
            let tipped = abs(s.pitch ?? 0) > 1e-6
            func circle(_ r: Double) -> [P2] { (0..<n).map { k in let t = 2 * .pi * Double(k) / Double(n); return P2(r * cos(t), r * sin(t)) } }
            // A ring in plan, moved by the shape's place when it is its own.
            func ring() -> [P2]? {
                if let o = s.outline, let r = source.ring(o) { return ccw(r) }
                if let poly = s.polygon?.filter({ $0.count == 2 }).map({ P2($0[0], $0[1]) }), poly.count >= 3 { return ccw(poly) }
                return nil
            }
            switch s.kind {
            case "box":
                guard let size = s.size, size.count == 3 else { return }
                let (a, b, c) = (size[0] / 2, size[1] / 2, size[2])
                let corners = [(-a, -b), (a, -b), (a, b), (-a, b)]
                face(corners.map { f.p($0.0, $0.1, 0) }, f.dir(0, 0, -1), colour)
                face(corners.map { f.p($0.0, $0.1, c) }, f.dir(0, 0, 1), colour)
                for k in 0..<4 {
                    let (p0, p1) = (corners[k], corners[(k + 1) % 4])
                    let mid = ((p0.0 + p1.0) / 2, (p0.1 + p1.1) / 2)
                    face([f.p(p0.0, p0.1, 0), f.p(p1.0, p1.1, 0), f.p(p1.0, p1.1, c), f.p(p0.0, p0.1, c)], f.dir(mid.0, mid.1, 0), colour)
                }
            case "cylinder", "cone":
                guard let r = s.radius, let h = s.height else { return }
                let rt = s.kind == "cone" ? (s.radius_top ?? 0) : (s.radius_top ?? r)
                let lo = circle(r), hi = circle(rt)
                for k in 0..<n {
                    let (p0, p1) = (lo[k], lo[(k + 1) % n]), (q0, q1) = (hi[k], hi[(k + 1) % n])
                    let mid = (p0 + p1) / 2
                    let quad = [f.p(p0.x, p0.y, 0), f.p(p1.x, p1.y, 0), f.p(q1.x, q1.y, h), f.p(q0.x, q0.y, h)]
                    face(quad.reduce(into: [V3]()) { out, p in if out.last.map({ simd_length($0 - p) > 1e-9 }) ?? true { out.append(p) } },
                         f.dir(mid.x, mid.y, (r - rt) / max(h, 1e-9) * r), colour)
                }
                if base > 0.01 || tipped { face(lo.reversed().map { f.p($0.x, $0.y, 0) }, f.dir(0, 0, -1), colour) }
                if rt > 1e-6 { face(hi.map { f.p($0.x, $0.y, h) }, f.dir(0, 0, 1), colour) }
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
                if !whole, base > 0.01 || tipped { face((0..<n).reversed().map { at(0, $0) }, f.dir(0, 0, -1), colour) }
            case "prism":
                guard let outer = ring(), let top = s.top, top > base else { return }
                let holes = (s.holes ?? []).map { ccw($0.filter { $0.count == 2 }.map { P2($0[0], $0[1]) }) }.filter { $0.count >= 3 }
                walls(outer, base, top, colour)
                for hole in holes { walls(hole.reversed(), base, top, colour) }
                cap(outer, holes: holes, top, up: true, colour)
                if base > 0.01 { cap(outer, holes: holes, base, up: false, colour) }
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
                if base > 0.01, profile[0][0] > 1e-6 { cap(rr.map { c + ($0 - c) * profile[0][0] }, base + profile[0][1], up: false, colour) }
            default:
                break
            }
        }

        // MARK: Sculptures

        /// A box standing on `c`, `lu` along `u` by `lv` along `v`.
        func box(_ c: P2, _ u: P2, _ v: P2, _ lu: Double, _ lv: Double, _ z0: Double, _ z1: Double, _ colour: String) {
            let a = u * (lu / 2), b = v * (lv / 2)
            prism(ccw([c - a - b, c + a - b, c + a + b, c - a + b]), z0, z1, colour)
        }

        /// A sculpture of a shape, `h` tall, facing `u`, standing at `c` on `z`.
        func sculpture(_ shape: String, _ c: P2, _ u: P2, _ v: P2, _ z: Double, _ h: Double, _ w: Double, _ colour: String) {
            switch shape {
            case "horse":
                horse(c, u, v, z, h, colour)
            case "quadriga":
                let hh = h * 0.72, step = max(w, hh * 1.4) / 4
                for k in 0..<4 { horse(c + u * (h * 0.25) + v * ((Double(k) - 1.5) * step), u, v, z, hh, colour) }
                box(c - u * (h * 0.7), u, v, h * 0.55, h * 0.65, z + h * 0.05, z + h * 0.5, colour)
                box(c - u * (h * 0.45), u, v, h * 0.08, h * 0.65, z + h * 0.5, z + h * 0.62, colour)
                figure(c - u * (h * 0.78), u, v, z + h * 0.45, h * 0.55, colour)
            case "equestrian":
                horse(c, u, v, z, h * 0.75, colour)
                figure(c, u, v, z + h * 0.55, h * 0.45, colour)
            case "obelisk":
                let a = u * (w / 2), b = v * (w / 2)
                loft(ccw([c - a - b, c + a - b, c + a + b, c - a + b]), c, z, [(1, 0), (0.62, h * 0.86), (0, h)], colour)
            case "cross":
                let t = max(0.08, h * 0.08)
                box(c, u, v, t, t, z, z + h, colour)
                box(c, u, v, t, h * 0.6, z + h * 0.68, z + h * 0.68 + t, colour)
            case "star":
                star(c, u, v, z + h / 2, h / 2, colour)
            default:
                figure(c, u, v, z, h, colour)
            }
        }

        /// A standing person in three blocks: legs, torso, head.
        func figure(_ c: P2, _ u: P2, _ v: P2, _ z: Double, _ h: Double, _ colour: String) {
            box(c, u, v, h * 0.2, h * 0.3, z, z + h * 0.48, colour)
            box(c, u, v, h * 0.22, h * 0.38, z + h * 0.48, z + h * 0.83, colour)
            let r = h * 0.09
            let head = (0..<8).map { k -> P2 in let t = Double(k) / 8 * 2 * .pi; return c + P2(cos(t), sin(t)) * r }
            prism(head, z + h * 0.83, z + h, colour)
        }

        /// A horse `h` tall to its head, facing `u`: body, four legs, neck,
        /// head and tail.
        func horse(_ c: P2, _ u: P2, _ v: P2, _ z: Double, _ h: Double, _ colour: String) {
            box(c, u, v, h * 1.0, h * 0.3, z + h * 0.45, z + h * 0.78, colour)
            for du in [-0.38, 0.38] {
                for dv in [-0.1, 0.1] { box(c + u * (h * du) + v * (h * dv), u, v, h * 0.09, h * 0.09, z, z + h * 0.46, colour) }
            }
            box(c + u * (h * 0.5), u, v, h * 0.2, h * 0.18, z + h * 0.66, z + h * 0.96, colour)
            box(c + u * (h * 0.66), u, v, h * 0.3, h * 0.15, z + h * 0.8, z + h * 0.97, colour)
            box(c - u * (h * 0.52), u, v, h * 0.08, h * 0.08, z + h * 0.5, z + h * 0.76, colour)
        }

        /// A five-pointed star standing upright, its face toward `u`, `r`
        /// to a point, centred at `zc`.
        func star(_ c: P2, _ u: P2, _ v: P2, _ zc: Double, _ r: Double, _ colour: String) {
            let t = max(0.1, r * 0.2)
            let pts: [(P2, Double)] = (0..<10).map { k in
                let rr = k % 2 == 0 ? r : r * 0.4, a = Double.pi / 2 + Double(k) * .pi / 5
                return (c + v * (rr * cos(a)), zc + rr * sin(a))
            }
            func p(_ q: (P2, Double), _ side: Double) -> V3 { let s = q.0 + u * (side * t / 2); return V3(s.x, s.y, q.1) }
            let front = V3(u.x, u.y, 0), centre: (P2, Double) = (c, zc)
            for k in 0..<10 {
                let e0 = pts[k], e1 = pts[(k + 1) % 10]
                tri(p(centre, 1), p(e0, 1), p(e1, 1), front, colour)
                tri(p(centre, -1), p(e0, -1), p(e1, -1), -front, colour)
                let mid = ((e0.0 + e1.0) / 2 - c, (e0.1 + e1.1) / 2 - zc)
                face([p(e0, 1), p(e1, 1), p(e1, -1), p(e0, -1)], V3(mid.0.x, mid.0.y, mid.1), colour)
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
