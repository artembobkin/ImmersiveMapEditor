import Foundation
import Geometry
import GLTF

/// Landmarks: the hand-made models of ~/Desktop/Modeling, read only, never
/// changed there, and the downloaded models of landmarks/models/ (fitted to
/// OSM by the fit tool), each fitted to the tile by hand through its recipe
/// in landmarks/models.json. Every model has a `placement.json` (its GLB,
/// the coordinate of its origin and the OSM elements it replaces) and a GLB
/// in metres around that origin.
///
/// A model whose origin lies within `modelReach` of the work area is brought
/// into the tile the way the engine's baker places it: its origin moved to
/// its coordinate, its metres scaled by the Mercator scale there against the
/// tile's, standing on the ground. The OSM buildings it replaces are left
/// out of the procedural build.
///
/// The model is repainted in the tile's palette, no atlas:
///
/// - Faces are grouped into panels (neighbours turned less than about 25
///   degrees from each other), and each panel takes the colour that covers
///   most of it in the model's atlas (the wall around a window, not the
///   window), replaced by the nearest of the palette's landmark colours, the
///   same in every tile, or by the one glass colour. The recipe can repaint
///   a colour by hand. A panel never breaks into a mosaic of triangles.
/// - The windows the atlas draws on a flat wall become geometry, as an
///   ordinary building's: a recess `windowDepth` deep, its reveals and glass
///   in tones of the wall. Where the windows do not come out whole, the
///   facade's rhythm does: a window where the atlas's dark columns and rows
///   cross, on the model's own bays and storeys. Then the model's geometry:
///   windows between its pilasters, on the storeys its cornices mark. A wall
///   with none of these gets the bays its recipe gives, measured by hand from
///   the model's previews (bays: pitch, storey, window, plinth), or else the
///   ordinary building's grid (fill_windows), so every facade reads as one.
///   On a skyscraper the glass is bright blue.
/// - Each face takes its colour's .lit, .side or .shade tone by where it
///   looks, as every wall of the tile does.
public enum Imported {
    static let modelReach = 400.0
    /// Glass in the models' atlases: blue and teal greys, all painted lm_glass.
    static let glass: [(Int, Int, Int)] = [(126, 157, 176), (92, 126, 142), (72, 100, 116), (142, 176, 186),
                                           (104, 138, 152), (150, 182, 176), (96, 150, 150)]
    /// Cosine: neighbours turned less than about 25 degrees from each other
    /// are one panel, so a low-poly dome or vault is one surface, not a mosaic
    /// of facets.
    static let panelAngle = 0.9
    static let flatCosine = 0.9995      // faces of one flat wall, for its windows
    static let windowGrid = 0.2         // metres between the samples of a wall's atlas
    static let windowDepth = 0.22
    static let pierReach = 1.5          // metres in front of a wall where its pilasters and cornices are looked for
    static let mullion = 1              // grid cells: bars between panes this thin are closed over
    static let windowSize = ((0.5, 5.0), (0.7, 6.0))    // width, height ranges of a window, metres
    static let roofFace = 12.0          // m²: a glass face looking up this large is a roof, not glass
    static let skyscraper = 100.0       // metres: a taller model has bright blue glass
    static let kind = "landmarks"

    /// One face of a model in the tile's metres.
    public final class Face {
        public var corners: [V3] = []
        public var uvs: [P2]?
        public var image: String?
        public var colour: (Int, Int, Int) = (200, 200, 200)
        public var area = 0.0
        public var normal = V3.zero
    }

    /// A model read, repainted and ready to build.
    public struct Model {
        public let id: String
        public let origin: P2
        public let faces: [Face]
        let images: [String: GLTF.Image]
        public let family: [String]
        let windows: Bool
        let fill: Bool
        let bays: [String: Any]?
        let glass: String?
    }

    struct Placement {
        let id: String
        let glb: URL
        let origin: P2
        let latitude: Double
        let altitude: Double
        let replaces: Set<String>
    }

    static func recipes() -> [String: [String: Any]] {
        let url = pipelineRoot.appendingPathComponent("landmarks/models.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json["models"] as? [String: [String: Any]] ?? [:]
    }

    /// A model's recipe: its own entry, else the longest matching prefix
    /// entry ("kremlin-*"), over the defaults.
    static func recipe(_ ident: String, _ book: [String: [String: Any]]) -> [String: Any] {
        var out = book["default"] ?? [:]
        var colours = out["colours"] as? [String: String] ?? [:]
        let prefixes = book.keys.filter { $0.hasSuffix("*") && ident.hasPrefix(String($0.dropLast())) }
            .sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }
        for k in prefixes + (book[ident] != nil ? [ident] : []) {
            let entry = book[k]!
            for (key, value) in entry where key != "colours" { out[key] = value }
            for (key, value) in entry["colours"] as? [String: String] ?? [:] { colours[key] = value }
        }
        out["colours"] = colours
        return out
    }

    /// The placements of the models near `work`.
    static func placements(_ tile: Tile, _ work: Geometry) -> [Placement] {
        let (x0, y0, x1, y1) = work.buffer(modelReach).bounds
        let fm = FileManager.default
        var paths: [String] = []
        let base = modelingRoot.appendingPathComponent("14")
        if let walk = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in walk where url.lastPathComponent == "placement.json" {
                // 14/*/*/**/placement.json: two folders at least below 14.
                if url.pathComponents.count - base.pathComponents.count >= 3 { paths.append(url.path) }
            }
        }
        paths.sort()
        let own = pipelineRoot.appendingPathComponent("landmarks/models")
        paths += ((try? fm.contentsOfDirectory(atPath: own.path)) ?? []).sorted().compactMap { name in
            let p = own.appendingPathComponent(name).appendingPathComponent("placement.json").path
            return fm.fileExists(atPath: p) ? p : nil
        }
        var found: [Placement] = []
        for path in paths where !path.contains("_revisions") && !path.contains("/sources/") {
            guard let data = fm.contents(atPath: path),
                  let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let o = p["origin"] as? [String: Any], let lat = (o["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (o["longitude"] as? NSNumber)?.doubleValue, let model = p["model"] as? String, !model.isEmpty
            else { continue }
            let xy = tile.metres(lat: lat, lon: lon)
            let glb = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(model)
            guard x0 <= xy.x, xy.x <= x1, y0 <= xy.y, xy.y <= y1, fm.fileExists(atPath: glb.path) else { continue }
            var ids = Set<String>()
            if let r = p["replaces"] as? [String: [Any]] {
                for v in r.values { for i in v { ids.insert("\(i)") } }
            } else if let r = p["replaces"] as? [Any] {
                for i in r { ids.insert("\(i)") }
            }
            found.append(Placement(id: p["id"] as? String ?? "", glb: glb, origin: xy, latitude: lat,
                                   altitude: (p["altitude_m"] as? NSNumber)?.doubleValue ?? 0, replaces: ids))
        }
        return found
    }

    // MARK: Reading a model

    /// The faces of one model in the tile's metres, with their atlas UVs, and
    /// the atlases.
    static func readModel(_ place: Placement, _ tile: Tile) throws -> ([Face], [String: GLTF.Image]) {
        let (triangles, images) = try GLTF.read(place.glb)
        let scale = cos(tile.centreLatitude * .pi / 180) / cos(place.latitude * .pi / 180)
        // A model stands on the ground plane.
        let offset = V3(place.origin.x, place.origin.y, place.altitude + Level.ground)
        var faces: [Face] = []
        for t in triangles {
            let f = Face()
            f.corners = t.corners.map { $0 * scale + offset }
            f.image = t.image
            f.uvs = t.uvs
            f.colour = f.image != nil ? mainColour(f, images) : t.base
            let n = (f.corners[1] - f.corners[0]).cross(f.corners[2] - f.corners[0])
            f.normal = n.length > 1e-12 ? n.normalized : n
            f.area = n.length / 2
            faces.append(f)
        }
        return (faces, images)
    }

    static func pixel(_ images: [String: GLTF.Image], _ name: String, _ u: Double, _ v: Double) -> SIMD3<Float> {
        let px = images[name]!
        let fu = u - floor(u), fv = v - floor(v)
        return px.rgb(Int(fv * Double(px.height)) % px.height, Int(fu * Double(px.width)) % px.width)
    }

    /// The colour covering most of a face in its atlas: the corners pulled to
    /// the middle, and the middle, voted.
    static func mainColour(_ f: Face, _ images: [String: GLTF.Image]) -> (Int, Int, Int) {
        let uvs = f.uvs!
        let mid = uvs.reduce(P2.zero, +) / Double(uvs.count)
        var samples = [mid]
        for t in [0.35, 0.7] { for uv in uvs { samples.append(mid + (uv - mid) * t) } }
        var keys: [[Int]] = []
        for s in samples {
            let c = pixel(images, f.image!, s.x, s.y)
            keys.append([c.x, c.y, c.z].map { Int(($0 * 255).rounded(.toNearestOrEven)) / 12 * 12 + 6 })
        }
        // A tie goes where the Python build sent it: the first in the order
        // a CPython set of the keys iterates.
        var best = keys[0], most = 0
        for k in pythonSetOrder(keys) {
            let n = keys.filter { $0 == k }.count
            if n > most { best = k; most = n }
        }
        return (min(255, best[0]), min(255, best[1]), min(255, best[2]))
    }

    /// CPython's hash of a tuple of small non-negative ints (xxHash based,
    /// Objects/tupleobject.c).
    static func pythonHash(_ t: [Int]) -> UInt64 {
        let p1: UInt64 = 11_400_714_785_074_694_791, p2: UInt64 = 14_029_467_366_897_019_727
        let p5: UInt64 = 2_870_177_450_012_600_261
        var acc = p5
        for v in t {
            acc &+= UInt64(v) &* p2
            acc = (acc << 31) | (acc >> 33)
            acc &*= p1
        }
        acc &+= UInt64(t.count) ^ (p5 ^ 3_527_539)
        return acc == UInt64.max ? 1_546_275_796 : acc
    }

    /// The distinct keys in the order `set(keys)` iterates them in CPython:
    /// open addressing, nine linear probes, then perturbation, the table
    /// growing from 8 slots to four times its use when three fifths full
    /// (Objects/setobject.c).
    static func pythonSetOrder(_ keys: [[Int]]) -> [[Int]] {
        var table: [[Int]?] = Array(repeating: nil, count: 8)
        var used = 0
        func insert(_ k: [Int], into t: inout [[Int]?]) -> Bool {
            let mask = t.count - 1
            let hash = pythonHash(k)
            var perturb = hash
            var i = Int(hash & UInt64(mask))
            while true {
                var probes = i + 9 <= mask ? 9 : 0
                var j = i
                while true {
                    if t[j] == nil { t[j] = k; return true }
                    if t[j]! == k { return false }
                    if probes == 0 { break }
                    probes -= 1
                    j += 1
                }
                perturb >>= 5
                i = Int((UInt64(i) &* 5 &+ 1 &+ perturb) & UInt64(mask))
            }
        }
        for k in keys where insert(k, into: &table) {
            used += 1
            if used * 5 >= (table.count - 1) * 3 {
                var size = 8
                while size <= used * 4 { size <<= 1 }
                var grown: [[Int]?] = Array(repeating: nil, count: size)
                for case let old? in table { _ = insert(old, into: &grown) }
                table = grown
            }
        }
        return table.compactMap { $0 }
    }

    // MARK: Panels and colours

    struct EdgeKey: Hashable {
        let a: SIMD3<Int64>, b: SIMD3<Int64>
    }

    /// Faces grouped by shared edges (by position: an importer splits
    /// vertices at UV seams) whose normals are closer than `limit` (a
    /// cosine), and on one plane if asked. Returns a group index per face.
    static func groups(_ faces: [Face], _ limit: Double, samePlane: Bool = false) -> [Int] {
        var parent = Array(faces.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        // Millimetres, rounded as Python's round(v, 3) rounds: the exact
        // binary value, so a value near a half rounds the way its digits say.
        func mm(_ v: Double) -> Int64 {
            let s = v * 1000, r = s.rounded(.toNearestOrEven)
            if abs(abs(s - r) - 0.5) > 1e-6 { return Int64(r) }
            return Int64((Double(String(format: "%.3f", v))! * 1000).rounded())
        }
        func key(_ c: V3) -> SIMD3<Int64> { SIMD3(mm(c.x), mm(c.y), mm(c.z)) }
        func less(_ a: SIMD3<Int64>, _ b: SIMD3<Int64>) -> Bool {
            a.x != b.x ? a.x < b.x : a.y != b.y ? a.y < b.y : a.z < b.z
        }
        var byEdge: [EdgeKey: [Int]] = [:]
        var order: [EdgeKey] = []
        for (i, f) in faces.enumerated() {
            let keys = f.corners.map(key)
            for k in keys.indices {
                let a = keys[k], b = keys[(k + 1) % keys.count]
                let e = less(b, a) ? EdgeKey(a: b, b: a) : EdgeKey(a: a, b: b)
                if byEdge[e] == nil { order.append(e) }
                byEdge[e, default: []].append(i)
            }
        }
        for e in order {
            let shared = byEdge[e]!
            let i = shared[0]
            for j in shared.dropFirst() {
                let fi = faces[i], fj = faces[j]
                if fi.normal.dot(fj.normal) <= limit { continue }
                if samePlane && abs((fj.corners[0] - fi.corners[0]).dot(fi.normal)) > 0.02 { continue }
                parent[find(j)] = find(i)
            }
        }
        return faces.indices.map(find)
    }

    /// The landmark colour nearest to an atlas colour, or glass.
    static func family(_ colour: (Int, Int, Int)) -> String {
        var best = "", bestD = Int.max
        let choices = Palette.landmark.map { (Palette.rgb($0.1), $0.0) } + glass.map { ($0, "lm_glass") }
        for (c, name) in choices {
            // Weighted for the eye: green counts most, blue least.
            let d = 2 * (c.0 - colour.0) * (c.0 - colour.0) + 4 * (c.1 - colour.1) * (c.1 - colour.1)
                + 3 * (c.2 - colour.2) * (c.2 - colour.2)
            if d < bestD { best = name; bestD = d }
        }
        return best
    }

    // MARK: Windows

    /// A flat wall's windows: its frame (origin, along, up, out), its
    /// outline in that frame, and the window rectangles.
    struct Wall {
        let origin, along, up, n: V3
        let outline: Geometry
        let rects: [Geometry]
    }

    /// The median of values, as numpy takes it.
    static func median(_ v: [Float]) -> Float {
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func rectangle(_ gx: [Double], _ gy: [Double], _ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) -> Geometry {
        let g = windowGrid
        return .box(gx[i0] - g / 2 + 0.04, gy[j0] - g / 2 + 0.04, gx[i1] + g / 2 - 0.04, gy[j1] + g / 2 - 0.04)
    }

    /// The windows the atlas draws on one flat wall (faces of one plane), as
    /// rectangles in the wall's own frame. nil if the wall shows no clear
    /// windows.
    static func wallWindows(_ faces: [Face], _ images: [String: GLTF.Image]) -> Wall? {
        let n = faces[0].normal
        if abs(n.z) > 0.1 || faces.contains(where: { $0.image == nil }) { return nil }
        let up = V3(0, 0, 1)
        let along = V3(-n.y, n.x, 0).normalized
        let origin = faces[0].corners[0]
        func flat(_ p: V3) -> P2 {
            let d = p - origin
            return P2(d.dot(along), d.dot(up))
        }
        let tris = faces.map { $0.corners.map(flat) }
        let outline = Geometry.unaryUnion(tris.map { Geometry.polygon($0) }.filter { $0.area > 1e-6 })
        if outline.isEmpty || outline.area < 8 { return nil }
        let (x0, y0, x1, y1) = outline.bounds
        let g = windowGrid
        let nx = Int((x1 - x0) / g) + 1, ny = Int((y1 - y0) / g) + 1
        if nx * ny > 400_000 { return nil }
        let gx = (0..<nx).map { x0 + (Double($0) + 0.5) * g }
        let gy = (0..<ny).map { y0 + (Double($0) + 0.5) * g }
        var cr = [Float](repeating: .nan, count: nx * ny), cg = cr, cb = cr
        for (f, t) in zip(faces, tris) {
            let a = t[0], b = t[1], c = t[2]
            let det = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            if abs(det) < 1e-9 { continue }
            let (ua, va) = (f.uvs![0].x, f.uvs![0].y), (ub, vb) = (f.uvs![1].x, f.uvs![1].y)
            let (uc, vc) = (f.uvs![2].x, f.uvs![2].y)
            let px = images[f.image!]!
            // Only the cells near the triangle's bounds can pass the test
            // (its tolerance is a share of the triangle, so a little more).
            let lx = min(a.x, b.x, c.x) - 0.01, hx = max(a.x, b.x, c.x) + 0.01
            let ly = min(a.y, b.y, c.y) - 0.01, hy = max(a.y, b.y, c.y) + 0.01
            let i0 = max(0, Int(((lx - x0) / g - 0.5).rounded(.up))), i1 = min(nx - 1, Int(((hx - x0) / g - 0.5).rounded(.down)))
            let j0 = max(0, Int(((ly - y0) / g - 0.5).rounded(.up))), j1 = min(ny - 1, Int(((hy - y0) / g - 0.5).rounded(.down)))
            if i0 > i1 || j0 > j1 { continue }
            for j in j0...j1 {
                for i in i0...i1 {
                    let X = gx[i], Y = gy[j]
                    let l1 = ((b.y - c.y) * (X - c.x) + (c.x - b.x) * (Y - c.y)) / det
                    let l2 = ((c.y - a.y) * (X - c.x) + (a.x - c.x) * (Y - c.y)) / det
                    let l3 = 1 - l1 - l2
                    guard l1 >= -1e-6, l2 >= -1e-6, l3 >= -1e-6 else { continue }
                    let u = l1 * ua + l2 * ub + l3 * uc, v = l1 * va + l2 * vb + l3 * vc
                    let fu = u - floor(u), fv = v - floor(v)
                    let p = px.rgb(Int(fv * Double(px.height)) % px.height, Int(fu * Double(px.width)) % px.width)
                    cr[j * nx + i] = p.x; cg[j * nx + i] = p.y; cb[j * nx + i] = p.z
                }
            }
        }
        let count = nx * ny
        let known = (0..<count).map { !cr[$0].isNaN }
        let knownCount = known.filter { $0 }.count
        if knownCount < 50 { return nil }
        let lum = (0..<count).map { cr[$0] * 0.3 + cg[$0] * 0.55 + cb[$0] * 0.15 }
        let idx = (0..<count).filter { known[$0] }
        let wall = median(idx.map { lum[$0] })
        let tint = SIMD3(median(idx.map { cr[$0] }), median(idx.map { cg[$0] }), median(idx.map { cb[$0] }))
        var raw = [Bool](repeating: false, count: count)
        for k in idx {
            let apart = ((cr[k] - tint.x) * (cr[k] - tint.x) + (cg[k] - tint.y) * (cg[k] - tint.y)
                         + (cb[k] - tint.z) * (cb[k] - tint.z)).squareRoot()
            // A window is darker than its wall, or a pane of light glass:
            // bluish in itself (white on a yellow wall is not), bluer than the
            // wall and clearly apart from it.
            let bluer = cb[k] - cr[k] > 0.03 && cb[k] - cr[k] > (tint.z - tint.x) + 0.06
            // Darker than the wall: by a share on a dark wall, by a step on a
            // light one, where windows are drawn light grey.
            raw[k] = lum[k] < max(wall * 0.72, wall - 0.15) || (apart > 0.12 && bluer)
        }
        // Mullions and glazing bars split a window into panes: a closing over
        // `mullion` joins them into one opening.
        var dark = shrink(grow(raw, nx, ny, mullion), nx, ny, mullion)
        for k in 0..<count where !known[k] { dark[k] = false }
        let share = Double(dark.filter { $0 }.count) / Double(knownCount)
        let rawShare = Double(raw.filter { $0 }.count) / Double(knownCount)
        if rawShare < 0.02 || rawShare > 0.8 { return nil }
        var rects: [Geometry] = []
        if 0.03 <= share && share <= 0.6 {
            var seen = [Bool](repeating: false, count: count)
            for j0 in 0..<ny {
                for i0 in 0..<nx where dark[j0 * nx + i0] && !seen[j0 * nx + i0] {
                    var cells: [(Int, Int)] = []
                    var queue = [(j0, i0)]
                    var head = 0
                    seen[j0 * nx + i0] = true
                    while head < queue.count {
                        let (j, i) = queue[head]
                        head += 1
                        cells.append((j, i))
                        for (dj, di) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let a = j + dj, c = i + di
                            if 0 <= a && a < ny && 0 <= c && c < nx && dark[a * nx + c] && !seen[a * nx + c] {
                                seen[a * nx + c] = true
                                queue.append((a, c))
                            }
                        }
                    }
                    let js = cells.map(\.0), iss = cells.map(\.1)
                    let w = Double(iss.max()! - iss.min()! + 1) * g
                    let h = Double(js.max()! - js.min()! + 1) * g
                    let ((wlo, whi), (hlo, hhi)) = windowSize
                    if !(wlo <= w && w <= whi && hlo <= h && h <= hhi) || Double(cells.count) < 0.5 * (w / g) * (h / g) {
                        continue
                    }
                    rects.append(rectangle(gx, gy, iss.min()!, js.min()!, iss.max()!, js.max()!))
                }
            }
        }
        let inner = outline.buffer(-0.12)
        rects = rects.filter { inner.contains($0) }
        if rects.count < 2 {
            // No whole windows to cut out: the facade's rhythm instead, the
            // columns and rows the atlas darkens, a window where they cross.
            rects = rhythm(raw, known, nx, ny, gx, gy).filter { inner.contains($0) }
        }
        if rects.count < 2 { return nil }
        return Wall(origin: origin, along: along, up: up, n: n, outline: outline, rects: rects)
    }

    /// Runs of a profile above its threshold, as (first, last) cell indices,
    /// of a length within `size` metres.
    static func runs(_ profile: [Double], _ cells: Double, _ size: (Double, Double)) -> [(Int, Int)] {
        let known = profile.filter { !$0.isNaN }
        if known.isEmpty { return [] }
        let mean = known.reduce(0, +) / Double(known.count)
        let std = (known.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(known.count)).squareRoot()
        let limit = max(0.15, mean + 0.5 * std)
        var out: [(Int, Int)] = []
        var start: Int?
        for (i, v) in (profile.map { $0.isNaN ? 0 : $0 } + [0]).enumerated() {
            if v > limit && start == nil {
                start = i
            } else if v <= limit, let s = start {
                if size.0 <= Double(i - s) * cells && Double(i - s) * cells <= size.1 { out.append((s, i - 1)) }
                start = nil
            }
        }
        return out
    }

    /// Windows where the atlas's dark columns and rows cross: the bays and
    /// storeys of the facade as drawn, when its windows do not come out whole.
    static func rhythm(_ dark: [Bool], _ known: [Bool], _ nx: Int, _ ny: Int, _ gx: [Double], _ gy: [Double]) -> [Geometry] {
        func share(_ cells: [Int]) -> Double {
            let k = cells.filter { known[$0] }.count
            return k == 0 ? .nan : Double(cells.filter { dark[$0] }.count) / Double(k)
        }
        let cols = (0..<nx).map { i in share((0..<ny).map { $0 * nx + i }) }
        let rows = (0..<ny).map { j in share((0..<nx).map { j * nx + $0 }) }
        let ((wlo, whi), (hlo, hhi)) = windowSize
        let g = windowGrid
        var columns = runs(cols, g, (wlo, whi))
        if columns.isEmpty {
            // Storeys drawn as bands with no bays to read: the bands' rows, on
            // the ordinary building's bays.
            let span = Double(gx.count - 1) * g
            let bays = Int(((span - 2 * Facade.corner) / Facade.bay).rounded(.down))
            let pitch = bays > 0 ? (span - 2 * Facade.corner) / Double(bays) : 0
            let half = Int(Facade.windowWidth / g / 2)
            for j in 0..<max(0, bays) {
                let c = Int((Facade.corner + (Double(j) + 0.5) * pitch) / g)
                columns.append((max(0, c - half), min(gx.count - 1, c + half)))
            }
        }
        var out: [Geometry] = []
        let rowRuns = runs(rows, g, (hlo, hhi))
        for (c0, c1) in columns {
            for (r0, r1) in rowRuns {
                var cell = 0, seen = 0
                for j in r0...r1 {
                    for i in c0...c1 {
                        if dark[j * nx + i] { cell += 1 }
                        if known[j * nx + i] { seen += 1 }
                    }
                }
                if seen > 0 && Double(cell) / Double(seen) > 0.35 { out.append(rectangle(gx, gy, c0, r0, c1, r1)) }
            }
        }
        return out
    }

    /// Windows on the model's own rhythm, from its geometry: the sides of its
    /// pilasters and piers (faces square to the wall within `pierReach` in
    /// front of it) give the bays, a window centred between two neighbours;
    /// the tops and soffits of its cornices and string courses (faces looking
    /// up or down there) give the storeys, a window in each. nil if the wall
    /// has fewer than two bays and one storey of that rhythm.
    static func geometryWindows(_ faces: [Face], _ members: [Int]) -> Wall? {
        let wall = members.map { faces[$0] }
        let n = wall[0].normal
        if abs(n.z) > 0.1 { return nil }
        let up = V3(0, 0, 1)
        let along = V3(-n.y, n.x, 0).normalized
        let origin = wall[0].corners[0]
        let outline = Geometry.unaryUnion(wall.filter { $0.area > 1e-6 }.map { f in
            Geometry.polygon(f.corners.map { P2(($0 - origin).dot(along), ($0 - origin).z) })
        })
        if outline.isEmpty || outline.area < 25 { return nil }
        let (x0, y0, x1, y1) = outline.bounds
        let inside = Set(members)
        var piers: [Double] = [], levels: [Double] = []
        for (i, f) in faces.enumerated() where !inside.contains(i) {
            let pts = f.corners.map { c -> (Double, Double, Double) in
                let d = c - origin
                return (d.dot(along), d.z, d.dot(n))
            }
            if !pts.allSatisfy({ -0.05 <= $0.2 && $0.2 <= pierReach }) { continue }
            if !pts.allSatisfy({ x0 - 0.5 <= $0.0 && $0.0 <= x1 + 0.5 }) { continue }
            if abs(f.normal.dot(along)) > 0.9 {
                let us = pts.map(\.0), zs = pts.map(\.1)
                if zs.max()! - zs.min()! > 2.0 { piers.append(us.reduce(0, +) / Double(us.count)) }
            } else if abs(f.normal.z) > 0.9 {
                levels.append(pts.map(\.1).reduce(0, +) / Double(pts.count))
            }
        }
        func cluster(_ values: [Double], _ gap: Double) -> [Double] {
            var out: [[Double]] = []
            for v in values.sorted() {
                if let last = out.last?.last, v - last < gap {
                    out[out.count - 1].append(v)
                } else {
                    out.append([v])
                }
            }
            return out.map { $0.reduce(0, +) / Double($0.count) }
        }
        piers = cluster(piers, 0.6)
        levels = [y0] + cluster(levels, 0.8).filter { y0 + 2.5 < $0 && $0 < y1 - 1.0 } + [y1]
        levels = cluster(levels, 2.5)
        let ((wlo, _), _) = windowSize
        let inner = outline.buffer(-0.3)
        var rects: [Geometry] = []
        for (a, c) in zip(piers, piers.dropFirst()) {
            let gap = c - a
            if !(1.8 <= gap && gap <= 9.0) { continue }
            let w = min(max(gap * 0.45, wlo), 3.0)
            let mid = (a + c) / 2
            for (lo, hi) in zip(levels, levels.dropFirst()) {
                let storey = hi - lo
                if storey < 2.6 { continue }
                let h = min(storey * 0.55, 4.0)
                let sill = lo + (storey - h) * 0.45
                let r = Geometry.box(mid - w / 2, sill, mid + w / 2, sill + h)
                if inner.contains(r) { rects.append(r) }
            }
        }
        if rects.count < 2 { return nil }
        return Wall(origin: origin, along: along, up: up, n: n, outline: outline, rects: rects)
    }

    /// For a flat wall whose atlas shows no windows the detector can read:
    /// the window grid of an ordinary building, storeys of about a floor,
    /// bays of a bay, windows of the ordinary size, those that fit whole in
    /// the wall. With `bays` (the recipe's), its pitch, storey, window and
    /// plinth instead. nil if the wall is too small for one row.
    static func gridWindows(_ faces: [Face], _ bays: [String: Any]?) -> Wall? {
        let n = faces[0].normal
        if abs(n.z) > 0.1 { return nil }
        let up = V3(0, 0, 1)
        let along = V3(-n.y, n.x, 0).normalized
        let origin = faces[0].corners[0]
        let tris = faces.map { f in Geometry.polygon(f.corners.map { P2(($0 - origin).dot(along), ($0 - origin).dot(up)) }) }
        let outline = Geometry.unaryUnion(tris.filter { $0.area > 1e-6 })
        if outline.isEmpty || outline.area < 25 { return nil }
        var (x0, y0, x1, y1) = outline.bounds
        if y1 - y0 < 3.5 || x1 - x0 < 3.0 { return nil }
        let spec = bays ?? [:]
        func number(_ key: String, _ fallback: Double) -> Double { (spec[key] as? NSNumber)?.doubleValue ?? fallback }
        let plinth = number("plinth", 0)
        let floors = max(1, Int(((y1 - y0 - plinth) / number("storey", Facade.floor)).rounded(.toNearestOrEven)))
        let storey = (y1 - y0 - plinth) / Double(floors)
        let count = Int(((x1 - x0 - 2 * Facade.corner) / number("pitch", Facade.bay)).rounded(.down))
        if count < 1 { return nil }
        let pitch = (x1 - x0 - 2 * Facade.corner) / Double(count)
        let size = (spec["window"] as? [NSNumber])?.map(\.doubleValue) ?? [Facade.windowWidth, Facade.windowHeight]
        let w = size[0]
        let h = min(size[1], storey * 0.7)
        y0 += plinth
        _ = y1
        let inner = outline.buffer(-0.3)
        var rects: [Geometry] = []
        for k in 0..<floors {
            let sill = y0 + Double(k) * storey + max(0.6, (storey - h) * 0.55)
            for j in 0..<count {
                let cx = x0 + Facade.corner + (Double(j) + 0.5) * pitch
                let r = Geometry.box(cx - w / 2, sill, cx + w / 2, sill + h)
                if inner.contains(r) { rects.append(r) }
            }
        }
        if rects.isEmpty { return nil }
        return Wall(origin: origin, along: along, up: up, n: n, outline: outline, rects: rects)
    }

    static func grow(_ mask: [Bool], _ nx: Int, _ ny: Int, _ cells: Int) -> [Bool] {
        var out = mask
        for _ in 0..<cells {
            var step = out
            for j in 0..<ny {
                for i in 0..<nx where !out[j * nx + i] {
                    if (j > 0 && out[(j - 1) * nx + i]) || (j < ny - 1 && out[(j + 1) * nx + i])
                        || (i > 0 && out[j * nx + i - 1]) || (i < nx - 1 && out[j * nx + i + 1]) {
                        step[j * nx + i] = true
                    }
                }
            }
            out = step
        }
        return out
    }

    static func shrink(_ mask: [Bool], _ nx: Int, _ ny: Int, _ cells: Int) -> [Bool] {
        grow(mask.map { !$0 }, nx, ny, cells).map { !$0 }
    }

    /// A flat wall rebuilt with its windows as recesses: the wall with holes,
    /// each window's four reveals and its glass at `windowDepth`.
    static func buildWall(_ b: Builder, _ wall: Wall, _ family: String, _ glass: String?, _ kind: String) -> Int {
        func at(_ u: Double, _ v: Double, _ depth: Double = 0) -> V3 {
            wall.origin + wall.along * u + wall.up * v - wall.n * depth
        }
        var made = 0
        for part in wall.outline.difference(.unaryUnion(wall.rects)).polygons {
            for tri in part.constrainedDelaunay() where tri.count == 3 {
                var p = tri.map { at($0.x, $0.y) }
                if (p[1] - p[0]).cross(p[2] - p[0]).dot(wall.n) < 0 { p = [p[0], p[2], p[1]] }
                if b.sided(p, family, kind) > 0 { made += 1 }
            }
        }
        let d = windowDepth
        for r in wall.rects {
            let (u0, v0, u1, v1) = r.bounds
            // Reveals face into the opening: bottom up, top down, sides inward.
            let quads: [((Double, Double), (Double, Double), V3)] = [
                ((u0, v0), (u1, v0), wall.up), ((u1, v1), (u0, v1), -wall.up),
                ((u1, v0), (u1, v1), -wall.along), ((u0, v1), (u0, v0), wall.along),
            ]
            for ((ua, va), (ub, vb), facing) in quads {
                var p = [at(ua, va), at(ub, vb), at(ub, vb, d), at(ua, va, d)]
                if (p[1] - p[0]).cross(p[2] - p[0]).dot(facing) < 0 { p = [p[0], p[3], p[2], p[1]] }
                b.sided(p, family + ".reveal", kind)
            }
            var p = [at(u0, v0, d), at(u1, v0, d), at(u1, v1, d), at(u0, v1, d)]
            if (p[1] - p[0]).cross(p[2] - p[0]).dot(wall.n) < 0 { p.reverse() }
            if let glass {
                b.flat(p, glass, kind)
            } else {
                b.sided(p, family + ".glass", kind)
            }
            made += 6
        }
        return made
    }

    // MARK: The landmarks of a tile

    /// The models near `work`, read and repainted, ready to build, the OSM
    /// elements they replace, and what they cover in plan.
    public static func load(_ tile: Tile, _ work: Geometry) -> (models: [Model], replaced: Set<String>, covered: Geometry) {
        let book = recipes()
        var models: [Model] = []
        var replaced = Set<String>()
        for place in placements(tile, work) {
            guard let (faces, images) = try? readModel(place, tile) else {
                print("[landmarks] cannot read \(place.glb.path)")
                continue
            }
            let recipe = recipe(place.id, book)
            let colours = recipe["colours"] as? [String: String] ?? [:]
            replaced.formUnion(place.replaces)
            let group = groups(faces, panelAngle)
            // Votes per panel, in the order the colours came, so a tie goes
            // to the first.
            var votes: [Int: [(String, Double)]] = [:]
            for (f, g) in zip(faces, group) {
                let atlas = family(f.colour)
                let fam = colours[atlas] ?? atlas
                var list = votes[g] ?? []
                if let k = list.firstIndex(where: { $0.0 == fam }) { list[k].1 += f.area } else { list.append((fam, f.area)) }
                votes[g] = list
            }
            var chosen: [Int: String] = [:]
            for (g, list) in votes {
                var best = list[0]
                for v in list.dropFirst() where v.1 > best.1 { best = v }
                chosen[g] = best.0
            }
            var fam = group.map { chosen[$0]! }
            // A roof the atlas paints blue-grey is not glass: the recipe's
            // flat_glass repaints each plane holding a large glass face looking
            // up (a roof, a slope), while the small facets of a dome or a vault
            // stay glass.
            if let flatGlass = recipe["flat_glass"] as? String {
                let planes = groups(faces, flatCosine, samePlane: true)
                var roofs = Set<Int>()
                for i in faces.indices where fam[i] == "lm_glass" && faces[i].normal.z > 0.05 && faces[i].area > roofFace {
                    roofs.insert(planes[i])
                }
                for (i, g) in planes.enumerated() where fam[i] == "lm_glass" && roofs.contains(g) { fam[i] = flatGlass }
            }
            // glass_below: real glass only up to this height, above it the
            // atlas's blue-grey is an attic or a roof, painted flat_glass.
            if let below = (recipe["glass_below"] as? NSNumber)?.doubleValue {
                let top = Level.ground + below
                let glassFaces = faces.indices.filter { fam[$0] == "lm_glass" }
                // Above glass_below only a dome stays glass: the glass within
                // dome_radius of the model's highest glass, in plan.
                var dome = Set<Int>()
                if !glassFaces.isEmpty, let radius = (recipe["dome_radius"] as? NSNumber)?.doubleValue, radius != 0 {
                    var peak = glassFaces[0]
                    for i in glassFaces where faces[i].corners.map(\.z).max()! > faces[peak].corners.map(\.z).max()! { peak = i }
                    func middle(_ f: Face) -> P2 {
                        P2(f.corners.map(\.x).reduce(0, +) / Double(f.corners.count),
                           f.corners.map(\.y).reduce(0, +) / Double(f.corners.count))
                    }
                    let p = middle(faces[peak])
                    for i in glassFaces where (middle(faces[i]) - p).length <= radius { dome.insert(i) }
                }
                for i in glassFaces where !dome.contains(i) && faces[i].corners.map(\.z).min()! > top {
                    fam[i] = recipe["flat_glass"] as? String ?? "lm_stone"
                }
            }
            let height = faces.isEmpty ? 0 : faces.flatMap { $0.corners.map(\.z) }.max()! - Level.ground
            let sky = recipe["skyscraper"] as? Bool ?? (height > skyscraper)
            models.append(Model(id: place.id, origin: place.origin, faces: faces, images: images, family: fam,
                                windows: recipe["windows"] as? Bool ?? true, fill: recipe["fill_windows"] as? Bool ?? true,
                                bays: recipe["bays"] as? [String: Any], glass: sky ? "lm_sky_glass" : nil))
        }
        // What the models cover in plan: an OSM building standing mostly under
        // a model is the model's too, listed in its `replaces` or not.
        var cover: [Geometry] = []
        for m in models {
            for f in m.faces where abs(f.normal.z) > 0.2 && f.corners.count >= 3 {
                cover.append(Geometry.polygon(f.corners.map { P2($0.x, $0.y) }).buffer(0.05))
            }
        }
        print("[landmarks] \(models.count) models: \(models.map(\.id).joined(separator: ", "))")
        return (models, replaced, .unaryUnion(cover))
    }

    /// The models with a face in `work`, in the tile's mesh: their flat walls
    /// with the atlas's windows as recesses, the rest face by face. Returns
    /// the faces made, the windows and the windows by model and by how they
    /// were found.
    public static func build(_ b: Builder, _ models: [Model], _ work: Geometry, region: Geometry? = nil)
        -> (made: Int, windows: Int, byModel: [String: [String: Int]]) {
        let (x0, y0, x1, y1) = work.bounds
        var made = 0, windows = 0
        var byModel: [String: [String: Int]] = [:]
        let landmarkNames = Set(Palette.landmark.map(\.0))
        for m in models {
            let faces = m.faces, family = m.family
            if faces.allSatisfy({ $0.corners.allSatisfy { $0.x < x0 || $0.x > x1 || $0.y < y0 || $0.y > y1 } }) { continue }
            var done = Set<Int>()
            if let region { b.whole = region.contains(m.origin) ? .whole : .foreign }
            if m.windows {
                let flat = groups(faces, flatCosine, samePlane: true)
                var walls: [Int: [Int]] = [:]
                var order: [Int] = []
                for (i, g) in flat.enumerated() {
                    if walls[g] == nil { order.append(g) }
                    walls[g, default: []].append(i)
                }
                for g in order {
                    let members = walls[g]!
                    var cover: [(String, Double)] = []
                    for i in members {
                        if let k = cover.firstIndex(where: { $0.0 == family[i] }) {
                            cover[k].1 += faces[i].area
                        } else {
                            cover.append((family[i], faces[i].area))
                        }
                    }
                    var best = cover[0]
                    for c in cover.dropFirst() where c.1 > best.1 { best = c }
                    let fam = best.0
                    // Glass, faces already repainted as a model's own window,
                    // or a colour of the tile's own (a roof) with no window tones.
                    if !landmarkNames.contains(fam) { continue }
                    var wall = wallWindows(members.map { faces[$0] }, m.images)
                    var how = "atlas"
                    if wall == nil && m.fill {
                        wall = geometryWindows(faces, members)
                        how = "geometry"
                    }
                    if wall == nil && m.fill {
                        // The atlas's windows did not read: the ordinary
                        // building's grid, so the facade reads as one.
                        wall = gridWindows(members.map { faces[$0] }, m.bays)
                        how = m.bays != nil ? "bays" : "grid"
                    }
                    guard let wall else { continue }
                    made += buildWall(b, wall, fam, m.glass, kind)
                    windows += wall.rects.count
                    var count = byModel[m.id] ?? ["atlas": 0, "grid": 0]
                    count[how, default: 0] += wall.rects.count
                    byModel[m.id] = count
                    done.formUnion(members)
                }
            }
            for (i, f) in faces.enumerated() where !done.contains(i) {
                let fam = family[i]
                let n = fam == "lm_glass" ? b.flat(f.corners, m.glass ?? fam, kind) : b.sided(f.corners, fam, kind)
                if n > 0 { made += 1 }
            }
        }
        if region != nil { b.whole = .cut }
        return (made, windows, byModel)
    }
}
