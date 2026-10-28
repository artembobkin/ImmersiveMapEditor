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
    /// The caricature. The map is seen from afar, and a detail under a metre
    /// is lost or turns to noise there, where a cartoon map (Zenly, Fenn)
    /// draws every cornice, pilaster and recess a size up. So the recipe
    /// gives the real sizes and the generator builds every detail at least
    /// this big (the user, 2026-10-27), the same on every building:
    /// - a plinth, band, pilaster or portal stands at least `proud` out;
    /// - a cornice is at least `corniceDepth` out and `corniceHeight` tall,
    ///   a plinth `plinthHeight`, a band `bandHeight`;
    /// - a window is cut `windowDepth` in, and drawn `windowScale` wider
    ///   and `windowRise` taller than given, within its bay and storey;
    /// - a parapet is at least `parapet`, eaves reach `eaves` with a fascia
    ///   `fascia` deep, a door is cut `doorDepth` in;
    /// - every convex corner of a mass or a box is chamfered `chamfer`
    ///   across (a toy's rounded edge, the user, 2026-10-27: a sharp corner
    ///   melts two flat faces into one from afar, the chamfer catches the
    ///   light between them), within a third of its edges;
    /// - windows come every `windowStep` metres at least, and no more than
    ///   `windowsAlong` on one wall (the bays merged to that), so they read
    ///   as windows and not as a texture;
    /// - a pilaster never stands on a window or a door (it moves to the gap
    ///   beside), a band is cut around every opening it would cross, so no
    ///   doorway is barred and no window crossed (the user, 2026-10-28);
    /// - a cone is at least `spireRadius` across at its foot and blunted
    ///   (`spireTip` of its radius at its tip), no taller than `spireAspect`
    ///   times its radius: a pinnacle, not a spike;
    /// - a flat roof always has a parapet (`parapet`), its cap the roofs'
    ///   own colour (`lm_roof`) unless the recipe says, and the parapet's
    ///   top a light rim that outlines the building from above.
    enum Caricature {
        static let proud = 0.45
        static let corniceDepth = 0.8, corniceHeight = 0.9
        static let plinthHeight = 0.9
        static let bandHeight = 0.4
        static let pilasterWidth = 0.8
        static let portalWidth = 0.6
        static let windowScale = 1.3, windowRise = 1.15
        static let parapet = 0.7
        static let eaves = 0.9, fascia = 0.6
        static let doorDepth = 0.8
        static let chamfer = 0.5
        static let windowStep = 4.5, windowsAlong = 14.0
        static let spireRadius = 1.0, spireTip = 0.25, spireAspect = 5.0
    }
    static let windowDepth = 0.45
    /// From this area a glazed opening is a shop front or a glazed arch,
    /// not a window, and shows the map's glass (`lm_glass`) at its back.
    static let glazedArea = 10.0

    /// What is wrong with a recipe, one line each: nothing when it builds.
    public static func check(_ r: LandmarkRecipe, _ source: LandmarkSource) -> [String] {
        var out: [String] = []
        let colours = Set(Palette.landmark.map(\.0) + LandmarkRecipe.glassColours)
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
            for (k, d) in (m.doors ?? []).enumerated() {
                if d.at.count != 2 { out.append("\(at).doors[\(k)]: needs at, [x, y], a point on or by the wall") }
                colour(d.colour, at + ".doors[\(k)]")
            }
            if let p = m.pilasters {
                if p.spacing <= 0.5 { out.append("\(at).pilasters: spacing must be over 0.5 m") }
                colour(p.colour, at + ".pilasters")
            }
            if let b = m.bands {
                if b.height <= 0 { out.append("\(at).bands: needs a height") }
                if m.windows == nil || m.windows!.storeys < 2 { out.append("\(at).bands: bands lie between storeys, so the mass needs windows of 2 storeys at least") }
                colour(b.colour, at + ".bands")
            }
            colour(m.roof?.colour, at + ".roof")
            if let p = m.roof?.parapet, p < 0 { out.append("\(at).roof: parapet below zero") }
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

    /// What is not physical in a recipe, one line each: what floats (a
    /// colonnade, a statue, a shape above the ground with nothing under it)
    /// and what leads nowhere (steps with no landing at their top). A
    /// photo seldom shows these, so the generator says them.
    public static func warnings(_ r: LandmarkRecipe, _ source: LandmarkSource) -> [String] {
        let solids = Solids(r, source)
        var out: [String] = []
        func p2(_ v: [Double]?) -> P2? { v.flatMap { $0.count == 2 ? P2($0[0], $0[1]) : nil } }
        for (i, f) in r.features.enumerated() {
            let base = f.base ?? 0
            switch f.kind {
            case "steps":
                guard let a = p2(f.from), let b = p2(f.to), let h = f.height, h > 0 else { continue }
                let d = b - a, len = simd_length(d)
                guard len > 1e-6 else { continue }
                // The landing side: the line's left (the building's).
                let n = P2(-d.y, d.x) / len, m = (a + b) / 2
                if !solids.inside(m + n * 0.4, base + h - 0.05) {
                    out.append("features[\(i)] (steps): they lead to nothing. At their top (\(f1(base + h)) m) there is no floor behind the line from \(f1(a.x)), \(f1(a.y)) to \(f1(b.x)), \(f1(b.y)): add a landing (a box, or a mass, from that line to the building at that height, the floor the columns and the doors stand on), or move the steps to the building's edge.")
                }
            case "colonnade":
                guard let a = p2(f.from), let b = p2(f.to), base > 0.3 else { continue }
                let n = max(2, f.columns ?? 2)
                let feet = (0..<n).map { a + (b - a) * (Double($0) / Double(n - 1)) }
                if feet.contains(where: { !solids.inside($0, base - 0.05) }) {
                    out.append("features[\(i)] (colonnade): it floats. Its base is \(f1(base)) m but nothing is under some of its columns: add the stylobate (a box under the whole colonnade from the ground to \(f1(base)) m), or set base 0.")
                }
            case "statue", "pediment":
                guard base > 0.3 else { continue }
                let at = p2(f.at) ?? (p2(f.from).flatMap { a in p2(f.to).map { ($0 + a) / 2 } })
                if let at, !solids.inside(at, base - 0.05) {
                    out.append("features[\(i)] (\(f.kind)): it floats at \(f1(base)) m with nothing under it: put it on a mass's top, a pediment, a pedestal, or a box.")
                }
            default:
                break
            }
        }
        for (i, s) in r.shapes.enumerated() {
            let base = s.base ?? 0
            guard base > 0.3, s.around == nil, s.repeat == nil else { continue }
            var at = p2(s.at)
            if at == nil, let ring = s.polygon?.filter({ $0.count == 2 }).map({ P2($0[0], $0[1]) }), ring.count >= 3 {
                at = ring.reduce(P2.zero, +) / Double(ring.count)
            }
            if let at, !solids.inside(at, base - 0.05) {
                out.append("shapes[\(i)] (\(s.kind)): it floats at \(f1(base)) m with nothing under its centre: stand it on a mass, a roof, or a shape, or sink it a little into what it is on.")
            }
        }
        return out
    }

    static func f1(_ v: Double) -> String { String(format: "%.1f", v) }

    /// The solids of a recipe, to ask whether a point is inside one: the
    /// masses with their roofs, the boxes, the shapes.
    struct Solids {
        var items: [(shape: Geometry, lo: Double, hi: Double)] = []

        init(_ r: LandmarkRecipe, _ source: LandmarkSource) {
            func poly(_ ring: [P2]) -> Geometry? { ring.count >= 3 ? Geometry.polygon(ring + [ring[0]]) : nil }
            for m in r.masses {
                let ring = m.outline.flatMap { source.ring($0) } ?? (m.polygon ?? []).filter { $0.count == 2 }.map { P2($0[0], $0[1]) }
                guard let g = poly(ring) else { continue }
                var top = m.top
                if let roof = m.roof, roof.shape != "flat" {
                    let c = g.centroid.xy, radius = ring.map { simd_length($0 - c) }.reduce(0, +) / Double(ring.count)
                    top += roof.height ?? radius * (roof.shape == "spire" ? 4 : roof.shape == "onion" ? 2.2 : 0.8)
                } else if let p = m.roof?.parapet { top += p }
                items.append((g, m.base, top))
            }
            for f in r.features where f.kind == "box" {
                let ring = (f.polygon ?? []).filter { $0.count == 2 }.map { P2($0[0], $0[1]) }
                if let g = poly(ring), let top = f.top { items.append((g, f.base ?? 0, top)) }
            }
            for f in r.features where f.kind == "colonnade" || f.kind == "steps" {
                // A colonnade's beam, and steps as a wedge: their footprint, from the ground to the top.
                guard let a = f.from, let b = f.to, a.count == 2, b.count == 2, let h = f.height else { continue }
                let p = P2(a[0], a[1]), q = P2(b[0], b[1]), d = q - p, len = simd_length(d)
                guard len > 1e-6 else { continue }
                let n = P2(d.y, -d.x) / len
                let reach = f.kind == "steps" ? (f.depth ?? Double(max(1, f.count ?? Int(h / 0.16))) * 0.35) : (f.radius ?? 0.6) + 0.3
                let side = f.kind == "steps" ? n * reach : n * reach
                let ring = f.kind == "steps" ? [p, q, q + side, p + side] : [p - side, q - side, q + side, p + side]
                if let g = poly(ring) { items.append((g, f.base ?? 0, (f.base ?? 0) + h)) }
            }
            for s in r.shapes {
                let base = s.base ?? 0
                var top = base
                var g: Geometry?
                switch s.kind {
                case "box":
                    guard let at = s.at, at.count == 2, let size = s.size, size.count == 3 else { continue }
                    let h = (s.heading ?? 0) * .pi / 180, u = P2(sin(h), cos(h)), v = P2(-cos(h), sin(h)), c = P2(at[0], at[1])
                    let a = u * (size[0] / 2), b = v * (size[1] / 2)
                    g = poly([c - a - b, c + a - b, c + a + b, c - a + b])
                    top = base + size[2]
                case "cylinder", "cone", "sphere", "dome":
                    guard let at = s.at, at.count == 2, let r = s.radius else { continue }
                    g = Geometry.point(P2(at[0], at[1])).buffer(r, quadSegs: 4)
                    top = base + (s.height ?? (s.kind == "sphere" ? 2 * r : r))
                case "prism":
                    let ring = s.outline.flatMap { source.ring($0) } ?? (s.polygon ?? []).filter { $0.count == 2 }.map { P2($0[0], $0[1]) }
                    g = poly(ring)
                    top = s.top ?? base
                case "loft":
                    if let own = s.polygon?.filter({ $0.count == 2 }).map({ P2($0[0], $0[1]) }), own.count >= 3 { g = poly(own) }
                    else if let o = s.outline, let ring = source.ring(o) { g = poly(ring) }
                    else if let at = s.at, at.count == 2, let r = s.radius { g = Geometry.point(P2(at[0], at[1])).buffer(r, quadSegs: 4) }
                    top = base + (s.profile?.compactMap { $0.count == 2 ? $0[1] : nil }.max() ?? 0)
                default:
                    continue
                }
                if let g, s.around == nil, s.repeat == nil { items.append((g, base, top)) }
            }
        }

        func inside(_ p: P2, _ z: Double) -> Bool {
            items.contains { z >= $0.lo - 0.05 && z <= $0.hi + 0.05 && $0.shape.contains(p) }
        }
    }

    /// The model of a recipe: its triangles by colour.
    public static func build(_ r: LandmarkRecipe, _ source: LandmarkSource) -> Model {
        let m = Model()
        var rings: [[P2]?] = r.masses.map { mass in
            let ring = mass.outline.flatMap { source.ring($0) } ?? (mass.polygon ?? []).filter { $0.count == 2 }.map { P2($0[0], $0[1]) }
            return ring.count >= 3 && mass.top > mass.base ? ccw(ring) : nil
        }
        snapOut(&rings, r.masses)
        sink(&rings, r.masses)
        sinkEdges(&rings, r.masses)
        rings = rings.map { $0.map { chamfered($0, Caricature.chamfer) } }
        for (k, mass) in r.masses.enumerated() {
            guard let ring = rings[k] else { continue }
            m.mass(ring, mass)
        }
        for f in r.features { m.feature(f) }
        for s in r.shapes { m.shape(s, source) }
        // The union makes the shell; when it fails outright, the faces on
        // one plane are at least pushed apart.
        if !m.unite() { m.separate() }
        m.cullHidden()
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
        /// Every triangle in the order it was made, with its colour and the
        /// closed solid it belongs to: what `separate` and `unite` work on.
        var faces: [(a: V3, b: V3, c: V3, colour: String, solid: Int)] = []
        /// The solid the faces made now belong to: every builder of a closed
        /// body begins one.
        var solid = 0
        func begin() { solid += 1 }
        /// How the union went: solids united, solids kept as they were.
        public private(set) var united = 0
        public private(set) var keptRaw = 0
        /// Triangles no outside camera could see, dropped (VisiblePass).
        public private(set) var hidden = 0

        /// Drops the triangles no camera around or above the model sees.
        func cullHidden() {
            let colours = tris.keys.sorted()
            var flat: [V3] = []
            var owner: [(String, Int)] = []
            for c in colours {
                let list = tris[c]!
                flat += list
                for t in stride(from: 0, to: list.count, by: 3) { owner.append((c, t)) }
            }
            guard !flat.isEmpty, let seen = VisiblePass.visible(flat) else { return }
            var out: [String: [V3]] = [:]
            for (k, (c, _)) in owner.enumerated() where seen[k] {
                out[c, default: []] += [flat[3 * k], flat[3 * k + 1], flat[3 * k + 2]]
            }
            hidden = owner.count - seen.filter { $0 }.count
            if ProcessInfo.processInfo.environment["LANDMARK_UNION_DEBUG"] != nil {
                var dropped: [String: Int] = [:]
                var shown = 0
                for (k, (c, _)) in owner.enumerated() where !seen[k] {
                    dropped[c, default: 0] += 1
                    if c == "rim", shown < 6 {
                        shown += 1
                        let (a, b, cc) = (flat[3 * k], flat[3 * k + 1], flat[3 * k + 2])
                        let n = simd_cross(b - a, cc - a)
                        FileHandle.standardError.write(Data(String(format: "  hidden rim: centre (%.1f, %.1f, %.1f), normal (%.2f, %.2f, %.2f), area %.3f\n",
                            (a.x + b.x + cc.x) / 3, (a.y + b.y + cc.y) / 3, (a.z + b.z + cc.z) / 3, n.x / simd_length(n), n.y / simd_length(n), n.z / simd_length(n), simd_length(n) / 2).utf8))
                    }
                }
                FileHandle.standardError.write(Data("hidden by colour: \(dropped.sorted { $0.value > $1.value })\n".utf8))
            }
            if ProcessInfo.processInfo.environment["LANDMARK_NO_CULL"] != nil { return }
            tris = out
        }

        public var triangles: Int { tris.values.reduce(0) { $0 + $1.count } / 3 }

        /// Two faces on one plane, one over the other, fight for the
        /// pixels (a landing's top on a stylobate's, a box flush with a
        /// wall): the one made later (the detail, not the wall) moves 2 cm
        /// out along its normal. Called once the model is whole.
        func separate() {
            // A face's own normal, and the plane's (the same for a face
            // looking the other way: a box's bottom on a mass's top).
            struct Face { let i: Int; let n: V3; let d: Double; let lo: V3; let hi: V3 }
            var planes: [String: [Face]] = [:]
            for (i, f) in faces.enumerated() {
                var n = simd_cross(f.b - f.a, f.c - f.a)
                let len = simd_length(n)
                guard len > 1e-9 else { continue }
                n /= len
                var plane = n
                if plane.z < -1e-6 || (abs(plane.z) <= 1e-6 && (plane.y < -1e-6 || (abs(plane.y) <= 1e-6 && plane.x < 0))) { plane = -plane }
                let key = String(format: "%.2f,%.2f,%.2f", plane.x, plane.y, plane.z)
                planes[key, default: []].append(Face(i: i, n: n, d: simd_dot(plane, f.a), lo: simd_min(simd_min(f.a, f.b), f.c), hi: simd_max(simd_max(f.a, f.b), f.c)))
            }
            var moved = Set<Int>()
            for group in planes.values where group.count > 1 {
                let sorted = group.sorted { $0.d < $1.d }
                for k in 0..<sorted.count {
                    let f = sorted[k]
                    guard !moved.contains(f.i) else { continue }
                    var j = k + 1
                    while j < sorted.count, sorted[j].d - f.d < 0.02 {
                        let g = sorted[j]
                        j += 1
                        guard !moved.contains(g.i), f.i != g.i,
                              f.lo.x < g.hi.x + 0.01, g.lo.x < f.hi.x + 0.01, f.lo.y < g.hi.y + 0.01, g.lo.y < f.hi.y + 0.01,
                              f.lo.z < g.hi.z + 0.01, g.lo.z < f.hi.z + 0.01 else { continue }
                        let later = max(f.i, g.i)
                        let t = faces[later]
                        var nn = simd_cross(t.b - t.a, t.c - t.a)
                        nn /= max(simd_length(nn), 1e-9)
                        let push = nn * 0.02
                        faces[later].a += push
                        faces[later].b += push
                        faces[later].c += push
                        moved.insert(later)
                    }
                }
            }
            guard !moved.isEmpty else { return }
            tris = [:]
            for f in faces { tris[f.colour, default: []] += [f.a, f.b, f.c] }
        }

        public var summary: String {
            let all = tris.values.flatMap { $0 }
            guard let first = all.first else { return "nothing built" }
            let lo = all.reduce(first) { simd_min($0, $1) }, hi = all.reduce(first) { simd_max($0, $1) }
            return String(format: "%d triangles (%d solids united into one shell%@%@), %.0f × %.0f m, %.1f m high, colours %@", triangles,
                          united, keptRaw > 0 ? ", \(keptRaw) kept apart, not closed" : "", hidden > 0 ? ", \(hidden) hidden dropped" : "",
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

        /// The solids united into one shell by Manifold: the faces grouped
        /// by solid, each welded into a mesh, the union's triangles coloured
        /// by the face they came from. A solid Manifold will not take (not
        /// closed, a face turned in) stays as it was, apart. Downward faces
        /// on the ground go: nothing sees them.
        @discardableResult
        func unite() -> Bool {
            var bySolid: [Int: [Int]] = [:]
            for (i, f) in faces.enumerated() { bySolid[f.solid, default: []].append(i) }
            let ids = bySolid.keys.sorted()
            // A face id a planar face of one colour in one solid, so the
            // union's simplification can merge the triangles of a face again.
            var groupOf: [String: Int] = [:]
            var groupColour: [String] = []
            func group(_ i: Int) -> UInt32 {
                let f = faces[i]
                var n = simd_cross(f.b - f.a, f.c - f.a)
                n /= max(simd_length(n), 1e-12)
                let key = String(format: "%d|%@|%.3f,%.3f,%.3f|%.3f", f.solid, f.colour, n.x, n.y, n.z, simd_dot(n, f.a))
                if let g = groupOf[key] { return UInt32(g) }
                groupOf[key] = groupColour.count
                groupColour.append(f.colour)
                return UInt32(groupColour.count - 1)
            }
            var meshes: [SolidUnion.Mesh] = []
            for id in ids {
                var index: [SIMD3<Int64>: UInt32] = [:]
                var mesh = SolidUnion.Mesh(verts: [], tris: [], faceIDs: [])
                func vertex(_ p: V3) -> UInt32 {
                    let key = SIMD3<Int64>(Int64((p.x * 10_000).rounded()), Int64((p.y * 10_000).rounded()), Int64((p.z * 10_000).rounded()))
                    if let k = index[key] { return k }
                    let k = UInt32(mesh.verts.count / 3)
                    index[key] = k
                    mesh.verts += [Float(Double(key.x) / 10_000), Float(Double(key.y) / 10_000), Float(Double(key.z) / 10_000)]
                    return k
                }
                for i in bySolid[id]! {
                    let f = faces[i]
                    let (a, b, c) = (vertex(f.a), vertex(f.b), vertex(f.c))
                    guard a != b, b != c, a != c else { continue }
                    mesh.tris += [a, b, c]
                    mesh.faceIDs.append(group(i))
                }
                meshes.append(mesh)
            }
            var statuses: [Int32] = []
            let result = SolidUnion.unite(meshes, statuses: &statuses)
            if ProcessInfo.processInfo.environment["LANDMARK_UNION_DEBUG"] != nil {
                var counts: [Int32: Int] = [:]
                for s in statuses { counts[s, default: 0] += 1 }
                // How many shells the union has: the triangles' vertex connectivity.
                var shells = 0
                if let result {
                    var parent = Array(0..<(result.verts.count / 3))
                    func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
                    for t in stride(from: 0, to: result.tris.count, by: 3) {
                        let a = find(Int(result.tris[t])), b = find(Int(result.tris[t + 1])), c = find(Int(result.tris[t + 2]))
                        parent[b] = a; parent[find(c)] = find(a)
                    }
                    var used = Set<Int>()
                    var size: [Int: Int] = [:], lo: [Int: V3] = [:], hi: [Int: V3] = [:]
                    for t in stride(from: 0, to: result.tris.count, by: 3) {
                        let root = find(Int(result.tris[t]))
                        used.insert(root)
                        size[root, default: 0] += 1
                        for k in 0..<3 {
                            let i = Int(result.tris[t + k]) * 3
                            let p = V3(Double(result.verts[i]), Double(result.verts[i + 1]), Double(result.verts[i + 2]))
                            lo[root] = simd_min(lo[root] ?? p, p)
                            hi[root] = simd_max(hi[root] ?? p, p)
                        }
                    }
                    shells = used.count
                    for (root, n) in size.sorted(by: { $0.value > $1.value }).prefix(12) {
                        let a = lo[root]!, b = hi[root]!
                        FileHandle.standardError.write(Data(String(format: "  shell: %d tris, x %.0f..%.0f y %.0f..%.0f z %.1f..%.1f\n", n, a.x, b.x, a.y, b.y, a.z, b.z).utf8))
                    }
                }
                FileHandle.standardError.write(Data("union: \(meshes.count) solids, statuses \(counts.sorted { $0.key < $1.key }), result \(result == nil ? "none" : "\(result!.faceIDs.count) triangles in \(shells) shells")\n".utf8))
                var reported = 0
                for (k, s) in statuses.enumerated() where s != 0 && reported < 12 {
                    reported += 1
                    let m = meshes[k]
                    // The halfedges: a closed, consistently wound mesh has every
                    // directed edge once and its opposite once.
                    var edges: [String: Int] = [:]
                    for t in stride(from: 0, to: m.tris.count, by: 3) {
                        for e in 0..<3 { edges["\(m.tris[t + e])>\(m.tris[t + (e + 1) % 3])", default: 0] += 1 }
                    }
                    var open = 0, doubled = 0
                    var samples: [String] = []
                    for (e, n) in edges {
                        let parts = e.split(separator: ">").map { Int($0)! }
                        let back = edges["\(parts[1])>\(parts[0])"] ?? 0
                        if n > 1 { doubled += 1 }
                        if back == 0 {
                            open += 1
                            if samples.count < 3 {
                                let p = Array(m.verts[(parts[0] * 3)..<(parts[0] * 3 + 3)]), q = Array(m.verts[(parts[1] * 3)..<(parts[1] * 3 + 3)])
                                samples.append(String(format: "(%.2f, %.2f, %.2f)-(%.2f, %.2f, %.2f)", p[0], p[1], p[2], q[0], q[1], q[2]))
                            }
                        }
                    }
                    FileHandle.standardError.write(Data("  solid \(ids[k]): status \(s), \(m.verts.count / 3) verts, \(m.tris.count / 3) tris, \(open) open halfedges, \(doubled) doubled, colours \(Set(bySolid[ids[k]]!.map { faces[$0].colour }).sorted()) e.g. \(samples.joined(separator: " "))\n".utf8))
                    if ProcessInfo.processInfo.environment["LANDMARK_UNION_DUMP"] == "\(ids[k])" {
                        for i in bySolid[ids[k]]! {
                            let f = faces[i]
                            FileHandle.standardError.write(Data(String(format: "    %@ (%.2f,%.2f,%.2f) (%.2f,%.2f,%.2f) (%.2f,%.2f,%.2f)\n", f.colour, f.a.x, f.a.y, f.a.z, f.b.x, f.b.y, f.b.z, f.c.x, f.c.y, f.c.z).utf8))
                        }
                    }
                }
            }
            guard let result else { return false }
            var out: [String: [V3]] = [:]
            for t in 0..<(result.faceIDs.count) {
                let id = Int(result.faceIDs[t])
                guard id < groupColour.count else { continue }
                func v(_ k: Int) -> V3 {
                    let i = Int(result.tris[3 * t + k]) * 3
                    return V3(Double(result.verts[i]), Double(result.verts[i + 1]), Double(result.verts[i + 2]))
                }
                let (a, b, c) = (v(0), v(1), v(2))
                let n = simd_cross(b - a, c - a)
                if n.z < 0, max(a.z, b.z, c.z) < 0.005 { continue }
                out[groupColour[id], default: []] += [a, b, c]
            }
            // The solids not taken, as they were.
            for (k, id) in ids.enumerated() where statuses[k] != 0 {
                for i in bySolid[id]! { out[faces[i].colour, default: []] += [faces[i].a, faces[i].b, faces[i].c] }
            }
            tris = out
            united = statuses.filter { $0 == 0 }.count
            keptRaw = statuses.count - united
            if let path = ProcessInfo.processInfo.environment["LANDMARK_UNION_OBJ"] {
                var obj = ""
                var n = 0
                for (colour, list) in out {
                    obj += "g \(colour)\n"
                    for p in list { obj += String(format: "v %.4f %.4f %.4f\n", p.x, p.y, p.z) }
                    for t in stride(from: 0, to: list.count, by: 3) { obj += "f \(n + t + 1) \(n + t + 2) \(n + t + 3)\n" }
                    n += list.count
                }
                try? obj.write(toFile: path, atomically: true, encoding: .utf8)
            }
            return true
        }

        // MARK: Faces

        /// A triangle turned to look along `hint`.
        func tri(_ a: V3, _ b: V3, _ c: V3, _ hint: V3, _ colour: String) {
            let n = simd_cross(b - a, c - a)
            guard simd_length(n) > 1e-9 else { return }
            let (p, q, r) = simd_dot(n, hint) >= 0 ? (a, b, c) : (a, c, b)
            tris[colour, default: []] += [p, q, r]
            faces.append((p, q, r, colour, solid))
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

        /// An opening cut into a wall, in (along, up): its ring, how deep,
        /// and what is at its back (glass, a door).
        struct Opening {
            let ring: [P2]
            let depth: Double
            let back: String
            /// What stands around it along the wall (a door's portal), kept
            /// clear of pilasters and bands too.
            var margin = 0.0
        }

        /// A door's place on a ring: the edge nearest it and where along.
        struct DoorAt {
            let edge: Int
            let t: Double
            let door: LandmarkRecipe.Door
        }

        func place(_ doors: [LandmarkRecipe.Door], on ring: [P2]) -> [DoorAt] {
            doors.compactMap { d -> DoorAt? in
                guard d.at.count == 2 else { return nil }
                let p = P2(d.at[0], d.at[1])
                var best: (Int, Double, Double)?
                for i in ring.indices {
                    let a = ring[i], b = ring[(i + 1) % ring.count], len = simd_length(b - a)
                    // Never a chamfer's edge: a door is on the wall beside it.
                    guard len > 2 else { continue }
                    let t = max(0, min(len, simd_dot(p - a, b - a) / len))
                    let dist = simd_length(a + (b - a) * (t / len) - p)
                    if best == nil || dist < best!.2 { best = (i, t, dist) }
                }
                return best.map { DoorAt(edge: $0.0, t: $0.1, door: d) }
            }
        }

        /// Walls of a ring from `z0` to `z1`, looking out (a counter-clockwise
        /// ring's right), with their windows and doors cut in: a window a
        /// recess of windowDepth, reveals a tone darker than the wall, the
        /// glass darker still, the sill light, as an ordinary building's; a
        /// door a deeper recess with its leaf at the back and a portal
        /// standing proud around it.
        /// An opening's place on a wall: its edge, its span along it and up.
        struct Cut {
            let edge: Int
            let t0: Double, t1: Double
            let z0: Double, z1: Double
        }

        @discardableResult
        func walls(_ ring: [P2], _ z0: Double, _ z1: Double, _ colour: String, windows: LandmarkRecipe.Windows? = nil,
                   doors: [DoorAt] = []) -> [Cut] {
            guard z1 > z0 else { return [] }
            var cuts: [Cut] = []
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count], len = simd_length(b - a)
                guard len > 1e-6 else { continue }
                let d = (b - a) / len, o = outward(a, b), o2 = P2(o.x, o.y)
                // A point of the wall: along it, up, and in from its face.
                func p(_ t: Double, _ z: Double, _ depth: Double = 0) -> V3 {
                    let q = a + d * t - o2 * depth
                    return V3(q.x, q.y, z)
                }
                var openings: [Opening] = []
                var spans: [(Double, Double, Double)] = []   // a door's t0, t1, top
                for at in doors where at.edge == i {
                    // A door stands on the wall's foot; a window (sill, glass) where it is told.
                    // A door's opening starts 2 cm up, so it stays inside the
                    // wall's face (an opening on the foot's edge is no opening).
                    let window = at.door.glass == true || (at.door.sill ?? 0) > 0.01
                    let sill = max(0.02, min(at.door.sill ?? 0, z1 - z0 - 1))
                    let w = min(at.door.width ?? (window ? 1.6 : 2.4), len * 0.6), h = min(at.door.height ?? (window ? 2.4 : 4), (z1 - z0 - sill) * 0.95)
                    let t = max(w / 2 + 0.3, min(len - w / 2 - 0.3, at.t))
                    guard t - w / 2 >= 0.2, t + w / 2 <= len - 0.2, h > 0.5 else { continue }
                    // A window's glass is a dark tone of its wall, as on an
                    // ordinary building; a large glazed opening (a shop front,
                    // a glazed arch) shows the map's glass itself.
                    let glazed = w * h >= LandmarkGenerator.glazedArea
                    openings.append(Opening(ring: opening(t, z0 + sill, w, h, arched: at.door.arched == true),
                                            depth: window ? LandmarkGenerator.windowDepth : max(at.door.depth ?? 0.6, Caricature.doorDepth),
                                            back: at.door.colour ?? (window ? (glazed ? "lm_glass" : "\(colour).glass") : "lm_dark"),
                                            margin: window ? 0 : max(at.door.portal ?? 0.35, Caricature.portalWidth)))
                    spans.append((t - w / 2, t + w / 2, z0 + sill + h))
                }
                if let w = windows {
                    for ring in self.openings(len, z0, z1, w) {
                        let t0 = ring.map(\.x).min()!, t1 = ring.map(\.x).max()!, bottom = ring.map(\.y).min()!
                        // Not over a door, nor on a window placed by hand.
                        guard !spans.contains(where: { t1 > $0.0 - 0.5 && t0 < $0.1 + 0.5 && bottom < $0.2 + 0.3 }) else { continue }
                        openings.append(Opening(ring: ring, depth: LandmarkGenerator.windowDepth, back: "\(colour).glass"))
                    }
                }
                for op in openings {
                    // A door's cut takes in its portal, and the portal's top.
                    cuts.append(Cut(edge: i, t0: op.ring.map(\.x).min()! - op.margin, t1: op.ring.map(\.x).max()! + op.margin,
                                    z0: op.ring.map(\.y).min()!, z1: op.ring.map(\.y).max()! + op.margin))
                }
                guard !openings.isEmpty else {
                    face([p(0, z0), p(len, z0), p(len, z1), p(0, z1)], o, colour)
                    continue
                }
                let shape = Geometry.polygon([P2(0, z0), P2(len, z0), P2(len, z1), P2(0, z1), P2(0, z0)],
                                             holes: openings.map { $0.ring + [$0.ring[0]] })
                for t in shape.constrainedDelaunay() where t.count == 3 {
                    tri(p(t[0].x, t[0].y), p(t[1].x, t[1].y), p(t[2].x, t[2].y), o, colour)
                }
                for op in openings {
                    let hole = op.ring, c = hole.reduce(P2.zero, +) / Double(hole.count)
                    for k in hole.indices {
                        let e0 = hole[k], e1 = hole[(k + 1) % hole.count]
                        let sill = abs(e0.y - e1.y) < 1e-9 && e0.y < c.y
                        let dir = c - (e0 + e1) / 2
                        face([p(e0.x, e0.y), p(e1.x, e1.y), p(e1.x, e1.y, op.depth), p(e0.x, e0.y, op.depth)],
                             V3(d.x * dir.x, d.y * dir.x, dir.y), sill ? "rim" : "\(colour).reveal")
                    }
                    face(hole.map { p($0.x, $0.y, op.depth) }, o, op.back)
                }
                // Portals: jambs and a lintel standing proud around each door,
                // solids of their own; the wall's solid goes on after them.
                let wallSolid = solid
                defer { solid = wallSolid }
                for at in doors where at.edge == i && at.door.glass != true && (at.door.sill ?? 0) <= 0.01 {
                    let w = min(at.door.width ?? 2.4, len * 0.6), h = min(at.door.height ?? 4, (z1 - z0) * 0.9)
                    let t = max(w / 2 + 0.3, min(len - w / 2 - 0.3, at.t)), pw = max(at.door.portal ?? 0.35, Caricature.portalWidth)
                    guard pw > 0.01, t - w / 2 >= 0.2, t + w / 2 <= len - 0.2, h > 1 else { continue }
                    let top = min(z0 + h + pw, z1)
                    let portal = at.door.colour.map { _ in "\(colour)" } ?? colour
                    proud(a, d, o2, t - w / 2 - pw, t - w / 2, z0, top, Caricature.proud, portal)
                    proud(a, d, o2, t + w / 2, t + w / 2 + pw, z0, top, Caricature.proud, portal)
                    proud(a, d, o2, t - w / 2, t + w / 2, z0 + h, top, Caricature.proud, portal)
                }
            }
            return cuts
        }

        /// A closed prism: its own solid.
        func prism(_ ring: [P2], _ z0: Double, _ z1: Double, _ colour: String) {
            begin()
            walls(ring, z0, z1, colour)
            cap(ring, z1, up: true, colour)
            cap(ring, z0, up: false, colour)
        }

        /// A block standing proud of a wall (from `a` along `d`, looking
        /// `o`), from `t0` to `t1` along it and `z0` to `z1` up, `depth` out,
        /// sunk 2 cm in so no face coincides with the wall's.
        func proud(_ a: P2, _ d: P2, _ o: P2, _ t0: Double, _ t1: Double, _ z0: Double, _ z1: Double, _ depth: Double, _ colour: String) {
            guard t1 > t0, z1 > z0 else { return }
            let ring = [a + d * t0 - o * 0.02, a + d * t1 - o * 0.02, a + d * t1 + o * depth, a + d * t0 + o * depth]
            prism(ccw(ring), z0, z1, colour)
        }

        /// One opening `w` wide and `h` tall standing on `z0` at `t`, in
        /// (along, up), arched or not.
        func opening(_ t: Double, _ z0: Double, _ w: Double, _ h: Double, arched: Bool) -> [P2] {
            let hw = w / 2
            if arched, h > w {
                let zt = z0 + h - hw
                var ring = [P2(t - hw, z0), P2(t + hw, z0), P2(t + hw, zt)]
                for j in 1..<6 {
                    let a = Double.pi * Double(j) / 6
                    ring.append(P2(t + hw * cos(a), zt + hw * sin(a)))
                }
                return ring + [P2(t - hw, zt)]
            }
            return [P2(t - hw, z0), P2(t + hw, z0), P2(t + hw, z0 + h), P2(t - hw, z0 + h)]
        }

        /// The window openings of a wall `len` long from `lo` to `hi`: a row
        /// a storey, spaced along the wall, never at its ends.
        func openings(_ len: Double, _ lo: Double, _ hi: Double, _ w: LandmarkRecipe.Windows) -> [[P2]] {
            guard w.storeys >= 1, hi - lo > 1, w.spacing > 0 else { return [] }
            let storey = (hi - lo) / Double(w.storeys)
            // The bays merged until the windows stand `windowStep` apart at
            // least, each window drawn wider in its wider bay.
            let step = w.spacing * max(1, (max(Caricature.windowStep, len / Caricature.windowsAlong) / w.spacing).rounded(.up))
            let height = min(w.height * Caricature.windowRise, storey * 0.7), width = min(w.width * Caricature.windowScale * (step / w.spacing).squareRoot(), step * 0.72)
            let n = Int((len - 1) / step)
            guard n >= 1, height > 0.3 else { return [] }
            var out: [[P2]] = []
            for k in 0..<n {
                let t = len / 2 + (Double(k) - Double(n - 1) / 2) * step
                for s in 0..<w.storeys {
                    let zc = lo + storey * (Double(s) + 0.5)
                    out.append(opening(t, zc - height / 2, width, height, arched: w.arched == true))
                }
            }
            return out
        }

        /// Pilasters along every wall long enough: between the windows when
        /// they share the spacing, else spaced from the middle.
        func pilasters(_ ring: [P2], _ lo: Double, _ hi: Double, _ p: LandmarkRecipe.Pilasters, cuts: [Cut], wall: String) {
            guard p.spacing > 0.5 else { return }
            let width = max(p.width ?? 1.0, Caricature.pilasterWidth), depth = max(p.depth ?? 0.3, Caricature.proud), colour = p.colour ?? wall
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count], len = simd_length(b - a)
                guard len > p.spacing + width else { continue }
                let d = (b - a) / len, o = outward(a, b), o2 = P2(o.x, o.y)
                let n = Int((len - 1) / p.spacing)
                // The openings of this wall, and the gaps between them a
                // pilaster fits in (0.2 m clear of each).
                let openings = cuts.filter { $0.edge == i }.map { ($0.t0 - 0.3, $0.t1 + 0.3) }.sorted { $0.0 < $1.0 }
                var gaps: [(Double, Double)] = []
                var from = 0.2
                for op in openings {
                    if op.0 - from >= width { gaps.append((from, op.0)) }
                    from = max(from, op.1)
                }
                if len - 0.2 - from >= width { gaps.append((from, len - 0.2)) }
                // The ideal places, spaced from the middle; each moved into
                // the nearest gap it fits, never onto an opening.
                let m = max(n, 1)
                var placed: [Double] = []
                for k in 0..<m {
                    let ideal = len / 2 + (Double(k) - Double(m - 1) / 2) * p.spacing
                    guard let gap = gaps.min(by: { abs(max($0.0 + width / 2, min($0.1 - width / 2, ideal)) - ideal) < abs(max($1.0 + width / 2, min($1.1 - width / 2, ideal)) - ideal) }) else { continue }
                    let t = max(gap.0 + width / 2, min(gap.1 - width / 2, ideal))
                    guard abs(t - ideal) <= p.spacing * 0.5, !placed.contains(where: { abs($0 - t) < width + 0.3 }) else { continue }
                    placed.append(t)
                }
                for t in placed {
                    proud(a, d, o2, t - width / 2, t + width / 2, lo, hi, depth, colour)
                }
            }
        }

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
            let cuts = walls(ring, lo, hi, m.colour, windows: m.windows, doors: doors)
            if plinth > 0 { walls(ring, m.base, lo, m.colour) }
            if cornice > 0 { walls(ring, hi, m.top, m.colour) }
            cap(ring, m.base, up: false, m.colour)
            let flat = m.roof == nil || m.roof?.shape == "flat"
            cap(ring, m.top, up: true, flat ? (m.roof?.colour ?? "lm_roof") : m.colour)
            if let p = m.plinth, plinth > 0 { band(ring, grown(ring, max(p.depth ?? 0.15, Caricature.proud)), m.base, lo, p.colour ?? "lm_stone") }
            if let c = m.cornice, cornice > 0 { band(ring, grown(ring, max(c.depth ?? 0.4, Caricature.corniceDepth)), hi, m.top, c.colour ?? "lm_white") }
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
            default:
                // The roof a closed solid: its slopes and gables over a flat
                // underside, with a fascia around the eaves when they overhang.
                begin()
                let over = (roof.overhang ?? 0.6) > 0.05 ? max(roof.overhang ?? 0.6, Caricature.eaves) : 0
                guard over > 0.05 else { return planes(ring, top, roof.shape, roof.height, colour, wall: wall, bottom: top) }
                let eave = grown(ring, over), fascia = Caricature.fascia
                planes(eave, top + fascia, roof.shape, roof.height, colour, wall: wall, bottom: top)
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
            begin()
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
                for k in 0..<n {
                    let (p0, p1) = (lo[k], lo[(k + 1) % n]), (q0, q1) = (hi[k], hi[(k + 1) % n])
                    let mid = (p0 + p1) / 2
                    let quad = [f.p(p0.x, p0.y, 0), f.p(p1.x, p1.y, 0), f.p(q1.x, q1.y, h), f.p(q0.x, q0.y, h)]
                    face(quad.reduce(into: [V3]()) { out, p in if out.last.map({ simd_length($0 - p) > 1e-9 }) ?? true { out.append(p) } },
                         f.dir(mid.x, mid.y, (r - rt) / max(h, 1e-9) * r), colour)
                }
                face(lo.reversed().map { f.p($0.x, $0.y, 0) }, f.dir(0, 0, -1), colour)
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
                if !whole { face((0..<n).reversed().map { at(0, $0) }, f.dir(0, 0, -1), colour) }
            case "prism":
                guard let outer = ring(), let top = s.top, top > base else { return }
                let holes = (s.holes ?? []).map { ccw($0.filter { $0.count == 2 }.map { P2($0[0], $0[1]) }) }.filter { $0.count >= 3 }
                walls(outer, base, top, colour)
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
            begin()
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

    /// Masses that touch or nearly touch sunk a little into each other, so
    /// the union makes one shell of them: a corner standing on a
    /// neighbour's wall, or within `near` of it, moves `into` metres inside
    /// that neighbour (where their heights overlap). Two masses built
    /// edge to edge, or with a slot between them, would stay two shells,
    /// with windows cut in walls no one sees.
    static func sink(_ rings: inout [[P2]?], _ masses: [LandmarkRecipe.Mass], near: Double = 0.6, into: Double = 0.3) {
        let polygons = rings.map { $0.map { Geometry.polygon($0 + [$0[0]]) } }
        for i in rings.indices {
            guard var ring = rings[i] else { continue }
            for k in ring.indices {
                let v = ring[k]
                for j in rings.indices where j != i {
                    guard let other = polygons[j], masses[i].base < masses[j].top - 0.05, masses[j].base < masses[i].top - 0.05 else { continue }
                    guard !other.contains(.point(v + (v - other.centroid.xy) * -1e-3)) || other.boundary.distance(.point(v)) < 1e-6 else { continue }
                    let d = other.boundary.distance(.point(v))
                    guard d < near else { continue }
                    // The nearest point of the neighbour's wall, and the way in.
                    let (_, on) = Geometry.point(v).nearestPoints(other.boundary)
                    let inward: P2
                    if d > 1e-6 {
                        inward = (on - v) / d
                    } else {
                        // On the wall itself: in is away from the centroid's far side.
                        let c = other.centroid.xy
                        inward = simd_length(c - v) > 1e-9 ? (c - v) / simd_length(c - v) : .zero
                    }
                    ring[k] = on + inward * into
                    break
                }
            }
            rings[i] = ring
        }
    }

    /// A taller mass's wall running inside a lower neighbour's wall, within
    /// `snap` of it and along it (a part read off the satellite view and
    /// placed a metre or two in from the outline, the user, 2026-10-28:
    /// two walls with two grids of windows, one seen through the other),
    /// pulled out onto the neighbour's wall along the stretch they share,
    /// so the facade is one wall from the ground to the taller top; then
    /// `sinkEdges` sinks the lower wall into it.
    static func snapOut(_ rings: inout [[P2]?], _ masses: [LandmarkRecipe.Mass], snap: Double = 2.5) {
        let original = rings
        for i in rings.indices {
            guard let ring = original[i] else { continue }
            var out: [P2] = []
            for k in ring.indices {
                let a = ring[k], b = ring[(k + 1) % ring.count]
                let d = b - a, len = simd_length(d)
                guard len > 1e-6 else { out.append(a); continue }
                let dir = d / len, n = P2(dir.y, -dir.x)
                var stretches: [(Double, Double, Double)] = []
                for j in original.indices where j != i {
                    // Only the taller wall moves, and only out to a neighbour
                    // that stands outside it.
                    guard let other = original[j], masses[i].top > masses[j].top + 0.05,
                          masses[i].base < masses[j].top - 0.05, masses[j].base < masses[i].top - 0.05 else { continue }
                    for m in other.indices {
                        let c = other[m], e = other[(m + 1) % other.count]
                        let f = e - c, flen = simd_length(f)
                        guard flen > 1e-6, abs(simd_dot(f / flen, dir)) > cos(10 * Double.pi / 180) else { continue }
                        let dc = simd_dot(c - a, n), de = simd_dot(e - a, n)
                        guard min(dc, de) > 0.05, max(dc, de) < snap, abs(dc - de) < 0.3 else { continue }
                        let t0 = max(0, min(simd_dot(c - a, dir), simd_dot(e - a, dir))), t1 = min(len, max(simd_dot(c - a, dir), simd_dot(e - a, dir)))
                        guard t1 - t0 > 3 else { continue }
                        stretches.append((t0, t1, (dc + de) / 2))
                    }
                }
                out.append(a)
                guard !stretches.isEmpty else { continue }
                stretches.sort { $0.0 < $1.0 }
                var cursor = 0.0
                for (t0, t1, far) in stretches where t0 >= cursor - 1e-6 {
                    let push = n * far
                    if t0 > cursor + 0.05 { out.append(a + dir * t0) }
                    out.append(a + dir * max(t0, cursor) + push)
                    out.append(a + dir * t1 + push)
                    if t1 < len - 0.05 { out.append(a + dir * t1) }
                    cursor = t1
                }
            }
            var cleaned: [P2] = []
            for p in out where cleaned.last.map({ simd_length($0 - p) > 1e-6 }) ?? true { cleaned.append(p) }
            if cleaned.count > 1, simd_length(cleaned[0] - cleaned[cleaned.count - 1]) < 1e-6 { cleaned.removeLast() }
            if cleaned.count >= 3 { rings[i] = cleaned }
        }
    }

    /// A wall running along a neighbour's wall within `near` of it (a
    /// slot between two masses, or two walls flush) pushed `into` metres
    /// into the neighbour along the stretch they share: the wall is split
    /// where the stretch begins and ends, and that piece moves. Deeper
    /// than a window's recess, so the windows of both walls end up inside
    /// the other mass and go with the union, instead of staying as sealed
    /// pockets in the wall. Corners far
    /// from the neighbour (a wider block beside a narrower one) leave `sink`
    /// nothing to do; this closes the slot itself.
    static func sinkEdges(_ rings: inout [[P2]?], _ masses: [LandmarkRecipe.Mass], near: Double = 0.6, into: Double = 0.3) {
        let original = rings
        for i in rings.indices {
            guard let ring = original[i] else { continue }
            var out: [P2] = []
            for k in ring.indices {
                let a = ring[k], b = ring[(k + 1) % ring.count]
                let d = b - a, len = simd_length(d)
                guard len > 1e-6 else { out.append(a); continue }
                let dir = d / len, n = P2(dir.y, -dir.x)   // the outside of a counter-clockwise ring
                // The stretches of this wall that face a neighbour's wall closely:
                // (from, to, how far the neighbour is).
                var stretches: [(Double, Double, Double)] = []
                for j in original.indices where j != i {
                    // The lower wall goes into the taller neighbour, where the
                    // whole of it hides; a taller wall pushed into a lower
                    // neighbour would step out above it.
                    guard let other = original[j], masses[i].base < masses[j].top - 0.05, masses[j].base < masses[i].top - 0.05,
                          masses[i].top <= masses[j].top + 0.05 else { continue }
                    for m in other.indices {
                        let c = other[m], e = other[(m + 1) % other.count]
                        let f = e - c, flen = simd_length(f)
                        guard flen > 1e-6, abs(simd_dot(f / flen, dir)) > cos(10 * Double.pi / 180) else { continue }
                        // How far out the neighbour's wall is, and where along ours it runs.
                        let dc = simd_dot(c - a, n), de = simd_dot(e - a, n)
                        guard min(dc, de) > -0.05, max(dc, de) < near else { continue }
                        let t0 = max(0, min(simd_dot(c - a, dir), simd_dot(e - a, dir))), t1 = min(len, max(simd_dot(c - a, dir), simd_dot(e - a, dir)))
                        guard t1 - t0 > 1 else { continue }
                        stretches.append((t0, t1, max(dc, de)))
                    }
                }
                out.append(a)
                guard !stretches.isEmpty else { continue }
                // The wall from a to b, its near stretches pushed out, in order.
                stretches.sort { $0.0 < $1.0 }
                var cursor = 0.0
                for (t0, t1, far) in stretches where t0 >= cursor - 1e-6 {
                    let push = n * (far + into)
                    if t0 > cursor + 0.05 { out.append(a + dir * t0) }
                    out.append(a + dir * max(t0, cursor) + push)
                    out.append(a + dir * t1 + push)
                    if t1 < len - 0.05 { out.append(a + dir * t1) }
                    cursor = t1
                }
            }
            // Points that fell together (a stretch to the corner) once.
            var cleaned: [P2] = []
            for p in out where cleaned.last.map({ simd_length($0 - p) > 1e-6 }) ?? true { cleaned.append(p) }
            if cleaned.count > 1, simd_length(cleaned[0] - cleaned[cleaned.count - 1]) < 1e-6 { cleaned.removeLast() }
            if cleaned.count >= 3 { rings[i] = cleaned }
        }
    }

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

private extension LandmarkGenerator.Model {
    func outward(_ a: P2, _ b: P2) -> V3 { LandmarkGenerator.outward(a, b) }
    func grown(_ ring: [P2], _ d: Double) -> [P2] { LandmarkGenerator.grown(ring, d) }
    func ccw(_ ring: [P2]) -> [P2] { LandmarkGenerator.ccw(ring) }
    func outwardOf(_ o: Geometry, _ a: P2, _ b: P2) -> V3 { LandmarkGenerator.outwardOf(o, a, b) }
}
