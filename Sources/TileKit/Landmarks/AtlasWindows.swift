import Foundation
import Geometry
import GLTF

/// The windows a model's atlas draws on a flat wall, read from the atlas
/// on a grid: whole windows, or the facade's rhythm where they do not come
/// out whole.
extension Imported {
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
                    let cellX = gx[i], cellY = gy[j]
                    let l1 = ((b.y - c.y) * (cellX - c.x) + (c.x - b.x) * (cellY - c.y)) / det
                    let l2 = ((c.y - a.y) * (cellX - c.x) + (a.x - c.x) * (cellY - c.y)) / det
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
}
