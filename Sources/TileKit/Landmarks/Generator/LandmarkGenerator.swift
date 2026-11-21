import CoreGraphics
import CoreText
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
    public static let roofShapes = ["flat", "gabled", "skillion", "hipped", "pyramidal", "dome", "onion", "spire", "mansard", "vault"]

    /// OSM's roof:shape in the recipe's words: the nearest of its shapes,
    /// flat for one it has no likeness of.
    public static func roofShape(osm: String) -> String {
        if roofShapes.contains(osm) { return osm }
        switch osm {
        case "half-hipped", "side_hipped", "hip": return "hipped"
        case "gambrel": return "mansard"
        case "round": return "vault"
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
    public static let statueShapes = ["figure", "horse", "quadriga", "equestrian", "obelisk", "cross", "star", "flame", "crescent"]
    public static let shapeKinds = ["box", "cylinder", "cone", "sphere", "dome", "prism", "loft", "text", "ring"]
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
        /// A cornice is a profile of three steps up and out: this much of
        /// its height and of its depth each.
        static let corniceSteps: [(height: Double, depth: Double)] = [(0.3, 0.35), (0.3, 0.7), (0.4, 1.0)]
        /// Every window's sill and surround (the user, 2026-11-01: more
        /// detail from the same words): the sill this deep and high, the
        /// jambs and lintel this wide and proud.
        static let sillDepth = 0.22, sillHeight = 0.14
        static let surroundWidth = 0.18, surroundDepth = 0.08
        /// Glazing: a glass solid gets a band at every storey and mullions
        /// along its walls, this thick, standing this proud, this far apart.
        static let mullion = 0.22, mullionProud = 0.2, mullionStep = 2.0, glazingStorey = 3.4
        /// The frame of the glass: a post at every corner this wide, a rail
        /// along the top and the bottom this high, so the volume reads as
        /// a framed body and not as a block with lines on it (the user,
        /// 2026-11-01).
        static let glassPost = 0.4, glassRail = 0.3
        static let plinthHeight = 0.9
        /// A plinth is a blind base: taller than this it is a storey with no
        /// windows, and the building stands on a pedestal (the user,
        /// 2026-11-03: the Four Seasons on 8 m of blind red). A ground floor
        /// of its own colour is a mass of its own, with its shop fronts.
        static let plinthTallest = 3.0
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
        /// A facade's walls keep one direction within this turn, and a wall
        /// shorter than `jog` between them is a jog (a pier's step), not a
        /// wall of its own: the windows run along the whole facade.
        static let facadeTurn = 15.0 * Double.pi / 180, jog = 1.2
        /// A glazed vault's ribs: their thickness and spacing along it.
        static let vaultRib = 0.2, vaultRibStep = 4.0
        /// What makes the building recognisable (`emphasis`), this much
        /// larger (the user, 2026-10-28: Zenly draws the one thing a person
        /// points at larger than life). The editor's Exaggeration setting,
        /// passed as LANDMARK_EMPHASIS; 3 when not set (the user, 2026-11-04: 3 by default).
        static var emphasis: Double {
            let v = Double(ProcessInfo.processInfo.environment["LANDMARK_EMPHASIS"] ?? "") ?? 3
            return min(5, max(1, v))
        }
    }
    static let windowDepth = 0.45
    /// From this area a glazed opening is a shop front or a glazed arch,
    /// not a window, and shows the map's glass (`lm_glass`) at its back.
    static let glazedArea = 10.0
    /// LANDMARK_WINDOWS_DEBUG prints every wall with the windows laid on it.
    static let windowsDebug = ProcessInfo.processInfo.environment["LANDMARK_WINDOWS_DEBUG"] != nil

    /// What is wrong with a recipe, one line each: nothing when it builds.
    public static func check(_ r: LandmarkRecipe, _ source: LandmarkSource) -> [String] {
        var out: [String] = []
        // Nothing in it is nothing to build: an empty recipe sent to see the
        // format built an empty model over St Basil's (the user, 2026-11-04).
        if r.masses.isEmpty && r.shapes.isEmpty && r.features.isEmpty {
            out.append("nothing to build: a recipe needs a mass, a shape or a feature at least (the format is in get_landmark)")
        }
        let colours = Set(Palette.landmark.map(\.0) + LandmarkRecipe.glassColours)
        func colour(_ c: String?, _ at: String) {
            if let c, !colours.contains(c) { out.append("\(at): colour \(c) is not one of \(colours.sorted().joined(separator: ", "))") }
        }
        for (i, m) in r.masses.enumerated() {
            let at = "masses[\(i)]" + (m.id.map { " (\($0))" } ?? "")
            if let o = m.outline, source.ring(o) == nil { out.append("\(at): outline \(o) is not one of the landmark's buildings") }
            if m.outline == nil, (m.polygon?.count ?? 0) < 3 { out.append("\(at): needs an outline or a polygon of 3 points at least") }
            for (c, cut) in (m.cuts ?? []).enumerated() where cut.from.count != 2 || cut.to.count != 2 || cut.keep.count != 2 {
                out.append("\(at).cuts[\(c)]: needs from, to and keep, each [x, y]")
            }
            for id in m.minus ?? [] where !r.masses.contains(where: { $0.id == id }) { out.append("\(at).minus: no mass with id \(id)") }
            if m.top <= m.base { out.append("\(at): top \(m.top) is not above base \(m.base)") }
            if m.base < 0 { out.append("\(at): base below the ground") }
            if let s = m.roof?.shape, !roofShapes.contains(s) { out.append("\(at): roof shape \(s) is not one of \(roofShapes.joined(separator: ", "))") }
            colour(m.colour, at)
            colour(m.roof?.colour, at + ".roof")
            colour(m.plinth?.colour, at + ".plinth")
            if let p = m.plinth, p.height > Caricature.plinthTallest {
                out.append("\(at).plinth: \(p.height) m is a storey, not a plinth (\(Int(Caricature.plinthTallest)) m at most, a blind base): "
                           + "a ground floor of its own colour, with its shop fronts, arches or windows, is a mass of its own from the ground to its top, "
                           + "and the body a mass from there up on the same outline (its base at the ground floor's top: the generator makes them touch and joins them)")
            }
            colour(m.cornice?.colour, at + ".cornice")
            colour(m.windows?.colour, at + ".windows")
            colour(m.frame, at + ".frame")
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
            colour(s.frame, at + ".frame")
            colour(s.windows?.colour, at + ".windows")
            if let w = s.windows, w.storeys < 1 || w.spacing <= 0 { out.append("\(at).windows: storeys and spacing must be positive") }
            for (k, d) in (s.doors ?? []).enumerated() {
                if d.at.count != 2 { out.append("\(at).doors[\(k)]: needs at, [x, y], a point on or by the wall") }
                colour(d.colour, at + ".doors[\(k)]")
            }
            if s.doors != nil, !["box", "prism"].contains(s.kind) || (s.pitch ?? 0) != 0 {
                out.append("\(at): doors go on an upright box or a prism")
            }
            if s.windows != nil, !["box", "prism", "cylinder"].contains(s.kind) || (s.pitch ?? 0) != 0 {
                out.append("\(at): windows go on an upright box, a prism or a cylinder (a round bay, a ribbon of windows a storey)")
            }
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
            case "ring":
                if (s.radius ?? 0) <= 0 { out.append("\(at): needs a radius") }
            case "text":
                if (s.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty { out.append("\(at): needs text") }
                if s.at?.count != 2 { out.append("\(at): needs at, [x, y]") }
                if (s.height ?? 0) <= 0 { out.append("\(at): needs a height, the capitals' in metres") }
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
        if out.isEmpty {
            let rings = footprints(r, source)
            for (i, m) in r.masses.enumerated() where rings[i] == nil && m.top > m.base {
                out.append("masses[\(i)]" + (m.id.map { " (\($0))" } ?? "") + ": its cuts or minus leave nothing of it")
            }
            if let shared = sharedWall(rings, r.masses) { out.append(shared) }
            out += overCourtyards(rings, r.masses, source)
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

    /// Masses stacked on one footprint made to touch exactly: an upper one
    /// whose base lies within a metre under the lower one's top sets that
    /// top (a storey of another colour over a ground floor). Overlapping,
    /// as the guide once asked, their walls lay in one plane over the
    /// overlap, and the union gave the band to both colours, a patchwork
    /// (the user, 2026-11-04: Nikolskaya Plaza, "z-fighting" at the top of
    /// its red ground floor). Touching, the union still joins them.
    static func stacked(_ rings: [[P2]?], _ masses: [LandmarkRecipe.Mass]) -> [LandmarkRecipe.Mass] {
        var out = masses
        let polygons = rings.map { $0.map { Geometry.polygon($0 + [$0[0]]) } }
        for i in out.indices {
            guard let lower = polygons[i] else { continue }
            for j in out.indices where j != i {
                guard let upper = polygons[j], out[j].base < out[i].top, out[j].base > out[i].top - 1,
                      out[j].base > out[i].base + 0.5 else { continue }
                // The same footprint: what is in one and not the other is next to nothing.
                guard lower.difference(upper).area + upper.difference(lower).area < max(1, lower.area * 0.02) else { continue }
                out[i].top = out[j].base
            }
        }
        return out
    }

    /// What the recipe asks for that the generator will not do, said back
    /// with the build rather than refusing it (an older recipe builds on):
    /// emphasis on anything but a sculpture or a finial standing free.
    public static func advice(_ r: LandmarkRecipe, _ source: LandmarkSource) -> [String] {
        var out: [String] = []
        // A part of an outline cut low where OSM gives the outline one
        // height and no parts (the user, 2026-11-04: a tower's west wing
        // made a 10 m podium off a lighter patch of roof in the satellite
        // view, against OSM's 19 storeys and the photo).
        let hasParts = source.buildings.contains(where: \.part)
        for (i, m) in r.masses.enumerated() {
            guard !hasParts, m.base < 1, let osm = m.outline, let b = source.buildings.first(where: { $0.osm == osm }),
                  !b.part, let height = b.height, height > 12, m.top < height * 0.6 else { continue }
            out.append(String(format: "masses[%d]%@: %.0f m high where OSM gives %@ one height of %.0f m and no parts: a wing lower than the rest needs a photo showing the step in the roofline; the satellite view tells roof colours and plan, never height, and a lighter patch of roof is not a lower wing",
                              i, m.id.map { " (\($0))" } ?? "", m.top, osm, height))
        }
        for (i, s) in r.shapes.enumerated() where s.emphasis == true && !["ring", "sphere"].contains(s.kind) {
            out.append("shapes[\(i)] (\(s.kind)): emphasis ignored, it is only for a sculpture or a finial standing free (a statue feature, a ring or a sphere shape); a \(s.kind) is drawn at its real size")
        }
        for (i, f) in r.features.enumerated() where f.emphasis == true && f.kind != "statue" {
            out.append("features[\(i)] (\(f.kind)): emphasis ignored, it is only for a sculpture or a finial standing free (a statue feature, a ring or a sphere shape); a \(f.kind) is drawn at its real size")
        }
        return out
    }

    /// The model of a recipe: its triangles by colour.
    public static func build(_ r: LandmarkRecipe, _ source: LandmarkSource) -> Model {
        let m = Model()
        var rings = footprints(r, source)
        sink(&rings, r.masses)
        sinkEdges(&rings, r.masses)
        rings = rings.map { $0.map { chamfered($0, Caricature.chamfer) } }
        for (k, mass) in stacked(rings, r.masses).enumerated() {
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
        return ([], ([model.summary] + advice(recipe, source)).joined(separator: "\n"))
    }
}
