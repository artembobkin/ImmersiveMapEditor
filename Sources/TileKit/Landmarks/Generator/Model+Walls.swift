import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// A model's faces and walls: a triangle, a face, a cap, the walls of a
/// ring with their openings (windows, doors, cut from the plinth up), the
/// windows laid along facades, the glazing of a glass mass, pilasters.
extension LandmarkGenerator.Model {
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
    /// `windowsFrom` is where the rows of windows and a hand-placed
    /// window's sill count from, the plinth's top, while the wall and its
    /// doors start at `z0`, the mass's foot: a door is cut from the
    /// ground through the plinth, never left standing on it (the user,
    /// 2026-11-02: the Ministry of Transport's entrances hung 5 m up on
    /// its dark plinth, the building as if lifted).
    func walls(_ ring: [P2], _ z0: Double, _ z1: Double, _ colour: String, windows: LandmarkRecipe.Windows? = nil,
               doors: [DoorAt] = [], windowsFrom: Double? = nil) -> [Cut] {
        guard z1 > z0 else { return [] }
        let foot = max(z0, min(z1 - 0.5, windowsFrom ?? z0))
        var cuts: [Cut] = []
        // The rows' windows of every wall, laid along the facades.
        let facade = windows.map { facadeWindows(ring, foot, z1, $0) } ?? [:]
        if LandmarkGenerator.windowsDebug, windows != nil {
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count], len = simd_length(b - a)
                let bearing = (atan2(b.x - a.x, b.y - a.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                print(String(format: "[windows] wall %d: %.1f m at %.0f°, %d windows, from (%.1f, %.1f)", i, len, bearing, facade[i]?.count ?? 0, a.x, a.y))
            }
        }
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
                // A door with a sill is a window of its own, laid from the
                // plinth's top as the rows are; a door's `glass` is a
                // glazed entrance, still cut from the foot (the user,
                // 2026-11-03: glass doors read as windows hung on the
                // Four Seasons' 8 m plinth, the hotel as if on a pedestal).
                let window = (at.door.sill ?? 0) > 0.01
                let sill = window ? max(0.02, foot - z0 + min(at.door.sill ?? 0, z1 - foot - 1)) : 0.02
                let w = min(at.door.width ?? (window ? 1.6 : 2.4), len * 0.6), h = min(at.door.height ?? (window ? 2.4 : 4), (z1 - z0 - sill) * 0.95)
                let t = max(w / 2 + 0.3, min(len - w / 2 - 0.3, at.t))
                guard t - w / 2 >= 0.2, t + w / 2 <= len - 0.2, h > 0.5 else { continue }
                // A window's glass is a dark tone of its wall, as on an
                // ordinary building; a large glazed opening (a shop front,
                // a glazed arch) shows the map's glass itself.
                let glazed = w * h >= LandmarkGenerator.glazedArea
                openings.append(Opening(ring: opening(t, z0 + sill, w, h, arched: at.door.arched == true),
                                        depth: window ? LandmarkGenerator.windowDepth : max(at.door.depth ?? 0.6, Caricature.doorDepth),
                                        back: at.door.colour ?? (window ? (glazed ? "lm_glass" : "\(colour).glass") : at.door.glass == true ? "lm_glass" : "lm_dark"),
                                        margin: window ? 0 : max(at.door.portal ?? 0.35, Caricature.portalWidth)))
                spans.append((t - w / 2, t + w / 2, z0 + sill + h))
            }
            // The windows' openings (the rows' and the hand-placed), for
            // their sills and surrounds.
            var panes: [[P2]] = doors.filter { $0.edge == i && ($0.door.sill ?? 0) > 0.01 }
                .compactMap { at in openings.first { $0.margin == 0 && abs($0.ring.map(\.x).min()! + $0.ring.map(\.x).max()! - 2 * at.t) < 1 }?.ring }
            if windows != nil {
                for ring in facade[i] ?? [] {
                    let t0 = ring.map(\.x).min()!, t1 = ring.map(\.x).max()!, bottom = ring.map(\.y).min()!
                    // Not over a door, nor on a window placed by hand.
                    guard !spans.contains(where: { t1 > $0.0 - 0.5 && t0 < $0.1 + 0.5 && bottom < $0.2 + 0.3 }) else { continue }
                    openings.append(Opening(ring: ring, depth: LandmarkGenerator.windowDepth, back: "\(colour).glass"))
                    panes.append(ring)
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
            for at in doors where at.edge == i && (at.door.sill ?? 0) <= 0.01 {
                let w = min(at.door.width ?? 2.4, len * 0.6), h = min(at.door.height ?? 4, (z1 - z0) * 0.9)
                let t = max(w / 2 + 0.3, min(len - w / 2 - 0.3, at.t)), pw = max(at.door.portal ?? 0.35, Caricature.portalWidth)
                guard pw > 0.01, t - w / 2 >= 0.2, t + w / 2 <= len - 0.2, h > 1 else { continue }
                let top = min(z0 + h + pw, z1)
                let portal = at.door.colour.map { _ in "\(colour)" } ?? colour
                proud(a, d, o2, t - w / 2 - pw, t - w / 2, z0, top, Caricature.proud, portal)
                proud(a, d, o2, t + w / 2, t + w / 2 + pw, z0, top, Caricature.proud, portal)
                proud(a, d, o2, t - w / 2, t + w / 2, z0 + h, top, Caricature.proud, portal)
            }
            // Every window's sill, and its surround, jambs and a lintel
            // standing a little proud, unless the wall is told plain (the
            // user, 2026-11-01: more detail from the same words).
            if windows?.surround != false {
                let light = windows?.colour ?? "lm_white", sw = Caricature.surroundWidth
                for pane in panes {
                    let t0 = pane.map(\.x).min()!, t1 = pane.map(\.x).max()!
                    let bottom = pane.map(\.y).min()!, top = pane.map(\.y).max()!
                    guard t0 - sw >= 0.05, t1 + sw <= len - 0.05, bottom - Caricature.sillHeight > z0 + 0.05, top + sw < z1 - 0.05 else { continue }
                    proud(a, d, o2, t0 - sw, t1 + sw, bottom - Caricature.sillHeight, bottom, Caricature.sillDepth, light)
                    proud(a, d, o2, t0 - sw, t0, bottom, top, Caricature.surroundDepth, light)
                    proud(a, d, o2, t1, t1 + sw, bottom, top, Caricature.surroundDepth, light)
                    proud(a, d, o2, t0 - sw, t1 + sw, top, top + sw, Caricature.surroundDepth, light)
                }
            }
        }
        return cuts
    }

    /// A closed prism: its own solid. One of glass is glazed.
    func prism(_ ring: [P2], _ z0: Double, _ z1: Double, _ colour: String) {
        begin()
        walls(ring, z0, z1, colour)
        cap(ring, z1, up: true, colour)
        cap(ring, z0, up: false, colour)
        if LandmarkRecipe.glassColours.contains(colour) { glazing(ring, z0, z1) }
    }

    /// The glazing of a glass solid (the user, 2026-11-01: a glass box or
    /// cylinder drawn plain was a block of blue plastic stuck on the
    /// facade): a frame in the frame's colour standing proud of the glass,
    /// at the map's caricature scale: a rail along the foot and the top,
    /// a post at every corner, a band at every storey line and mullions
    /// along every wall `spacing` apart. Solids of their own, so the
    /// union joins them to the glass.
    func glazing(_ ring: [P2], _ z0: Double, _ z1: Double, storey: Double = Caricature.glazingStorey,
                 spacing: Double? = nil, frame: String? = nil) {
        guard z1 - z0 > 0.5, ring.count >= 3 else { return }
        let frame = frame.flatMap { LandmarkRecipe.glassColours.contains($0) ? nil : $0 } ?? "lm_dark"
        let step = max(0.5, spacing ?? Caricature.mullionStep), m = Caricature.mullion, out = Caricature.mullionProud
        let rail = min(Caricature.glassRail, (z1 - z0) / 4), outer = grown(ring, out)
        // The frame: a rail along the foot and the top, a band at every
        // storey line between.
        band(ring, outer, z0, z0 + rail, frame)
        band(ring, outer, z1 - rail, z1, frame)
        let bands = max(0, Int(((z1 - z0) / storey).rounded(.down)))
        for k in 1...max(1, bands) where k <= bands && z0 + storey * Double(k) < z1 - rail - m {
            let z = z0 + storey * Double(k)
            band(ring, outer, z - m / 2, z + m / 2, frame)
        }
        // A post at every corner, mullions between: a corner of a round
        // ring (a cylinder's segments) is a mullion, not a post.
        let round = ring.count > 8
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count], len = simd_length(b - a)
            guard len > 1e-6 else { continue }
            let d = (b - a) / len, o = outward(a, b), o2 = P2(o.x, o.y)
            let post = round ? m : Caricature.glassPost
            proud(a, d, o2, 0, min(len, post / 2), z0, z1, out, frame)
            proud(a, d, o2, max(0, len - post / 2), len, z0, z1, out, frame)
            let n = max(1, Int((len / step).rounded()))
            for k in 1..<n {
                let t = len * Double(k) / Double(n)
                proud(a, d, o2, t - m / 2, t + m / 2, z0, z1, out, frame)
            }
        }
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
        // The bays merged until the windows stand about `windowStep` apart,
        // each window drawn wider in its wider bay: the next whole count
        // of bays up, unless the count is within a tenth of a whole one
        // (the user, 2026-11-05: at 2.2 m spacing, 2.05 bays, the windows
        // stood 6.6 m apart, and a Victorian house 11 m long got one; now
        // 4.4 m and two, while a 4 m spacing still merges to 8), and a wall that
        // fits one window with its margins gets one at least, in its
        // middle (a bay's angled 3 m walls had none).
        let bays = max(1, Int((max(Caricature.windowStep, len / Caricature.windowsAlong) / w.spacing - 0.1).rounded(.up)))
        let step = w.spacing * Double(bays)
        // A wall too short for the window at its size gets a narrower one,
        // 0.3 m in from its ends, 0.8 m wide at least: the corners are
        // chamfered, and a bay's 3.3 m wall is 2.3 m by then.
        let height = min(w.height * Caricature.windowRise, storey * 0.7)
        let width = min(w.width * Caricature.windowScale * Double(bays).squareRoot(), step * 0.72, max(0, len - 0.6))
        let n = max(Int((len - 1) / step), width >= 0.8 ? 1 : 0)
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

    /// The rows' windows of every wall of a ring, by the wall's index,
    /// laid along facades: a run of walls keeping one direction (within
    /// `Caricature.facadeTurn`), the jogs between them (walls under
    /// `Caricature.jog` long, a pier's step) skipped, is one facade, its
    /// windows spaced along its whole length by `openings` and each
    /// column cut into the wall it falls on, moved to the middle of that
    /// wall when it does not fit where it fell (a bay between piers). So
    /// a facade OSM draws as piers and bays gets its windows, where each
    /// bay alone was too short for one (the user, 2026-11-03: GUM's
    /// front had none). A wall standing alone is laid as before.
    func facadeWindows(_ ring: [P2], _ lo: Double, _ hi: Double, _ w: LandmarkRecipe.Windows) -> [Int: [[P2]]] {
        let n = ring.count
        var out: [Int: [[P2]]] = [:]
        guard n >= 3 else { return out }
        struct Edge { let a, b: P2; let len: Double; let d: P2 }
        let edges = (0..<n).map { i -> Edge in
            let a = ring[i], b = ring[(i + 1) % n], len = simd_length(b - a)
            return Edge(a: a, b: b, len: len, d: len > 1e-9 ? (b - a) / len : P2(1, 0))
        }
        // The runs, each the indices of its walls in order.
        var runs: [[Int]] = []
        var current: [Int] = []
        var dir = P2.zero
        for i in 0..<n {
            let e = edges[i]
            guard e.len > 1e-6 else { continue }
            if current.isEmpty {
                current = [i]
                dir = e.d
            } else if simd_dot(e.d, dir) > cos(Caricature.facadeTurn) {
                current.append(i)
            } else if e.len < Caricature.jog {
                continue
            } else {
                runs.append(current)
                current = [i]
                dir = e.d
            }
        }
        if !current.isEmpty { runs.append(current) }
        // The ring closes: a facade may run over its first corner.
        if runs.count >= 2, let last = runs.last, let first = runs.first,
           simd_dot(edges[last[0]].d, edges[first[0]].d) > cos(Caricature.facadeTurn) {
            runs[0] = last + first
            runs.removeLast()
        }
        for run in runs {
            let d = edges[run[0]].d, start = edges[run[0]].a
            let spans = run.map { (lo: simd_dot(edges[$0].a - start, d), hi: simd_dot(edges[$0].b - start, d)) }
            let length = spans.last!.hi
            guard length > 1 else { continue }
            // The columns of windows along the facade, by their place.
            var columns: [Double: [[P2]]] = [:]
            for r in openings(length, lo, hi, w) {
                let xs = r.map(\.x)
                columns[((xs.min()! + xs.max()!) / 2 * 1000).rounded() / 1000, default: []].append(r)
            }
            var placed: [Int: [Double]] = [:]
            for (t, rings) in columns.sorted(by: { $0.key < $1.key }) {
                let xs = rings[0].map(\.x), width = xs.max()! - xs.min()!
                guard let k = run.indices.first(where: { spans[$0].lo - 0.01 <= t && t <= spans[$0].hi + 0.01 }) else { continue }
                let i = run[k], e = edges[i]
                var local = t - spans[k].lo
                if local - width / 2 < 0.3 || local + width / 2 > e.len - 0.3 {
                    guard e.len >= width + 0.6 else { continue }
                    local = e.len / 2
                }
                if placed[i, default: []].contains(where: { abs($0 - local) < width + 0.4 }) { continue }
                placed[i, default: []].append(local)
                out[i, default: []] += rings.map { $0.map { P2($0.x + (local - t), $0.y) } }
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
}
