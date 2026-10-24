import CryptoKit
import Foundation
import Geometry
import simd

// Construction sites (`landuse=construction`): their ground is not drawn
// (the vector tile shows it), this file puts up what makes a site read as
// one from afar, all low-poly toys in the palette's prop colours:
//
// - a fence `fenceHeight` high along the site's edge: green panels, posts
//   standing above them, a light rail on top, broken where a building stands
//   on the edge;
// - a tower crane on every site of `craneArea` or more, one by every house
//   being built: a lattice mast, a jib with its trolley and hook, a
//   counter-jib with its weights, the ties from the mast's top, standing
//   above the houses around it;
// - on a site of `frameArea` or more, the concrete frame of a house being
//   built, one more for every `frameEach` (three at most);
// - site cabins along the fence, two side by side and one on top, and a row
//   of portable toilets by them;
// - then as many as the free ground holds (`mix`): excavators, bulldozers,
//   dump trucks full of earth, concrete mixers, mounds of dug earth, piles
//   of sand and gravel, stacks of concrete slabs, pallets of bricks, steel
//   pipes, concrete well rings.
//
// Things are placed on the whole OSM site, not on the part of it in the
// tile, so the tiles on either side of an edge place them alike and the cut
// joins. Each site takes its frame from its outline's long side. Candidate
// spots lie on a grid, tried from the site's middle out with a jitter fixed
// by the site, so a rebuild puts things in the same places. A thing that
// does not fit clear of the fence, the buildings, the roads and the others
// is left out.

private let fenceHeight = 2.4
private let fenceThick = 0.2
private let fenceRail = 0.25
private let fencePost = 3.0
private let craneArea = 1500.0
private let frameArea = 3000.0
private let frameEach = 10000.0
private let frameGap = 45.0
// The things a site is filled with: one of each kind per so many square
// metres of its free ground, at most `mixMax`, at least one if it is a kind a
// small site has too. In this order.
private let mix: [(String, Double)] = [
    ("excavator", 1500), ("soil", 2000), ("sand", 1500), ("gravel", 3000), ("slabs", 1500), ("bricks", 1500),
    ("pipes", 3000), ("rings", 3000), ("dump_truck", 5000), ("mixer", 8000), ("bulldozer", 6000),
]
private let mixMax = 8
// Machines are fewer than that: at most so many of each kind on a site.
private let mixCap = ["excavator": 3, "bulldozer": 2, "dump_truck": 3, "mixer": 2]
private let craneHeight = (36.0, 44.0)
private let craneJib = 30.0
private let craneCounter = 9.0
private let mast = 1.8
private let kind = "construction"

private func upright(_ b: Builder, _ c: P2, _ heading: Double, _ lx: Double, _ ly: Double, _ z0: Double,
                     _ h: Double, _ colour: String, bottom: Bool = false, top: Bool = true) {
    TileKit.upright(b, c, heading, lx, ly, z0, h, colour, kind, bottom: bottom, top: top)
}

private func bar(_ b: Builder, _ p: V3, _ q: V3, _ t: Double, _ colour: String) {
    TileKit.bar(b, p, q, t, colour, kind)
}

/// The fence along the sites' `earth` (Ground's construction earth) and the
/// things of every site touching `work`.
public func buildSites(_ b: Builder, osm: Osm, work: Geometry, earth: Geometry?, footprint: Geometry,
                       asphalt: Geometry) {
    guard let earth, !earth.isEmpty else { return }
    buildFence(b, earth, footprint)
    let taken = footprint.buffer(1.0).union(asphalt.buffer(1.0))
    for area in osm.areas() where area.tags["landuse"] == "construction" && area.shape.intersects(work) {
        for site in area.shape.polygons where site.area >= 300 {
            furnish(b, site, site.difference(taken))
        }
    }
}

/// Fence panels along the inside of the site's edge, sided like a wall, a
/// post every `fencePost` and at every corner standing above them, and a
/// light rail on top that outlines the site from above, as a cornice
/// outlines a building. Left out where a building stands on the edge.
private func buildFence(_ b: Builder, _ earth: Geometry, _ footprint: Geometry) {
    let keepOut = footprint.buffer(0.4)
    let inset = earth.buffer(-fenceThick, join: .mitre)
    var rings: [Geometry] = []
    for p in inset.polygons {
        rings.append(.lineString(p.exterior))
        for r in p.interiors where Geometry.polygon(r).area > 50 { rings.append(.lineString(r)) }
    }
    let line = Geometry.unaryUnion(rings).difference(keepOut).lineMerge()
    let pieces = line.lines.filter { $0.length > 1.0 }
    let z0 = Level.ground
    let z1 = z0 + fenceHeight
    let z2 = z1 + fenceRail
    for piece in pieces {
        slab(b, piece.buffer(fenceThick / 2, cap: .flat, join: .mitre), z0, z1, "fence")
        let rail = piece.buffer(fenceThick / 2 + 0.06, cap: .flat, join: .mitre)
        slab(b, rail, z1, z2, "fence_rail", down: true)
        for p in posts(piece) {
            upright(b, p, 0.0, 0.3, 0.3, z0, fenceHeight + fenceRail + 0.25, "fence_post")
        }
    }
}

/// A shape extruded from z0 to z1, its walls sided, its top lit, its
/// underside closed if asked for.
private func slab(_ b: Builder, _ shape: Geometry, _ z0: Double, _ z1: Double, _ colour: String, down: Bool = false) {
    for p in shape.polygons {
        for (a, c) in edges(p) {
            b.paint([v3(a, z0), v3(c, z0), v3(c, z1), v3(a, z1)], colour, kind)
        }
        b.fill(p, z1, colour, kind)
        if down { b.fill(p, z0, colour, kind, down: true) }
    }
}

/// Where a fence's posts stand: both ends, every corner, and evenly between
/// them no more than `fencePost` apart.
private func posts(_ line: Geometry) -> [P2] {
    let coords = line.coords
    var stops = [0.0]
    var run = 0.0
    for i in 1..<coords.count {
        run += simd_distance(coords[i - 1], coords[i])
        if i < coords.count - 1 {
            let a = coords[i - 1], c = coords[i], d = coords[i + 1]
            let turn = abs(atan2(d.y - c.y, d.x - c.x) - atan2(c.y - a.y, c.x - a.x))
            if min(turn, 2 * .pi - turn) < 15 * .pi / 180 { continue }
        }
        stops.append(run)
    }
    var spots: [Double] = []
    for (s0, s1) in zip(stops, stops.dropFirst()) {
        let n = max(1, Int(((s1 - s0) / fencePost).rounded(.up)))
        spots += (0..<n).map { s0 + (s1 - s0) * Double($0) / Double(n) }
    }
    spots.append(line.length)
    return spots.map { line.interpolate($0).xy }
}

// MARK: Placing

/// The angle of the site's long side, in degrees.
private func frame(_ site: Geometry) -> Double {
    let c = site.minimumRotatedRectangle.exterior
    let i = simd_distance(c[1], c[2]) > simd_distance(c[0], c[1]) ? 1 : 0
    return atan2(c[i + 1].y - c[i].y, c[i + 1].x - c[i].x) * 180 / .pi
}

/// Python's `round`: halves to even.
private func pyRound(_ v: Double) -> Int { Int(v.rounded(.toNearestOrEven)) }

/// The MD5 of the parts as Python's `repr` writes their tuple, in hex: what
/// fixes a site's choices, the same as the Python build made them.
private func rank(_ key: (Int, Int), _ parts: [Any]) -> String {
    let items = ["(\(key.0), \(key.1))"] + parts.map { p -> String in
        if let s = p as? String { return "'\(s)'" }
        return "\(p)"
    }
    let text = "(" + items.joined(separator: ", ") + ")"
    return Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// The number in hex digits `a..<b` of a rank.
private func hex(_ s: String, _ a: Int, _ b: Int) -> Int {
    let chars = Array(s)
    return Int(String(chars[a..<b]), radix: 16) ?? 0
}

/// Points sorted by a key, ties kept in order, as Python's sort keeps them.
private func sortedStable(_ pts: [P2], _ key: (P2) -> Double) -> [P2] {
    pts.map { ($0, key($0)) }.enumerated()
        .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
        .map { $0.element.0 }
}

/// The things of one site, on its `free` ground: the frame of the house
/// being built with its cranes beside it, cabins and toilets along the
/// fence, then machines, piles and stacks of materials as many as the
/// ground holds (one of each kind per so many square metres, `mix`).
private func furnish(_ b: Builder, _ site: Geometry, _ free: Geometry) {
    let angle = frame(site)
    let centroid = site.centroid.xy
    let key = (pyRound(centroid.x), pyRound(centroid.y))
    let inner = free.buffer(-1.5, join: .mitre)
    if inner.isEmpty { return }
    let prepared = Prepared(inner)
    let (x0, y0, x1, y1) = inner.bounds
    var spots: [P2] = []
    for i in 0...Int((x1 - x0) / 2) {
        for j in 0...Int((y1 - y0) / 2) {
            spots.append(P2(x0 + Double(i) * 2.0, y0 + Double(j) * 2.0))
        }
    }
    spots = spots.filter { prepared.contains($0) }
    let middle = site.contains(centroid) ? centroid : site.representativePoint.xy

    var jitters: [SIMD2<Int>: Double] = [:]
    func jitter(_ p: P2, _ scale: Double = 12.0) -> Double {
        let k = SIMD2(pyRound(p.x), pyRound(p.y))
        if jitters[k] == nil { jitters[k] = Double(hex(rank(key, [k.x, k.y]), 0, 4)) / 0xFFFF }
        return jitters[k]! * scale
    }
    spots = sortedStable(spots) { simd_distance(middle, $0) + jitter($0) }
    let edge = site.boundary
    var taken: [Geometry] = []

    /// A spot for a footprint lx by ly turned with the site, clear of the
    /// fence and of what is placed, keeping `clear` around it.
    func find(_ lx: Double, _ ly: Double, order: [P2]? = nil, turn: Double = 0, clear: Double = 1.5,
              test: ((P2) -> Bool)? = nil) -> P2? {
        let unit = Geometry.box(-lx / 2, -ly / 2, lx / 2, ly / 2).rotate(angle + turn, origin: .zero)
        for p in (order.map { $0.isEmpty ? spots : $0 } ?? spots) {
            if let test, !test(p) { continue }
            let rect = unit.translate(p.x, p.y)
            if prepared.contains(rect) && !taken.contains(where: { rect.intersects($0) }) {
                taken.append(rect.buffer(clear))
                return p
            }
        }
        return nil
    }

    func pick(_ name: String, _ k: Int, _ count: Int) -> Int { hex(rank(key, [name, k]), 0, 4) % count }
    func turnOf(_ name: String, _ k: Int) -> Double { Double(hex(rank(key, [name, k]), 0, 4)) / 0xFFFF * 2 * .pi }

    let heading = angle * .pi / 180
    let area = inner.area
    // The houses being built, one more for every `frameEach` of ground, the
    // next some `frameGap` from the first, each with a crane beside it. A
    // site too small for a house still gets a crane.
    var frames: [P2] = []
    if area >= frameArea {
        for k in 0..<min(3, 1 + Int(area / frameEach)) {
            let order = frames.isEmpty ? nil
                : sortedStable(spots) { abs(simd_distance(frames[0], $0) - frameGap) + jitter($0) }
            for (lx, ly) in [(24.0, 14.0), (18.0, 12.0), (12.0, 10.0)] {
                if let at = find(lx, ly, order: order, clear: 3.0) {
                    frames.append(at)
                    carcass(b, at, heading, lx, ly, 3 + pick("floors", k, 4))
                    break
                }
            }
        }
    }
    let near = frames.first ?? middle
    var placed: [P2] = []
    for (k, anchor) in (frames.isEmpty ? (area >= craneArea ? [middle] : []) : frames).enumerated() {
        let order = sortedStable(spots) { simd_distance(anchor, $0) + jitter($0, 4.0) }
        let test: (P2) -> Bool = { p in placed.allSatisfy { simd_distance(p, $0) > craneJib * 0.8 } }
        if let p = find(5.0, 5.0, order: order, test: test) {
            placed.append(p)
            crane(b, p, turnOf("jib", k), craneHeight.0 + (craneHeight.1 - craneHeight.0) * Double(k % 2))
        }
    }
    // Cabins and toilets along the fence.
    let byEdge = sortedStable(spots) { edge.distance(.point($0)) + 0.1 * simd_distance(middle, $0) }
    for k in 0..<(1 + Int(area / 9000)) {
        if let p = find(7.5, 3.6, order: byEdge) {
            cabins(b, p, heading, rank(key, ["cabins", k]))
            if let q = find(4.2, 1.4, order: sortedStable(spots) { simd_distance($0, p) }) {
                toilets(b, q, heading)
            }
        }
    }
    // Machines, piles and materials, each kind by its share of the ground,
    // in two places: a yard of materials by the frame, and the earthworks
    // away from it. Everything is square to the site, machines a little
    // askew.
    var pool = Array(spots.prefix(max(1, spots.count / 2)))
    let yard = spots.first { let d = simd_distance(near, $0); return d > 12 && d < 30 } ?? middle
    let close = pool.filter { simd_distance(near, $0) < 50 }
    if !close.isEmpty { pool = close }
    var digAt = middle
    if !pool.isEmpty {
        // The first of the farthest, as Python's max picks it.
        var best = -Double.infinity
        for p in pool where simd_distance(yard, p) > best {
            best = simd_distance(yard, p)
            digAt = p
        }
    }
    var orders: [P2: [P2]] = [:]
    func around(_ anchor: P2) -> [P2] {
        if let o = orders[anchor] { return o }
        let o = sortedStable(spots) { simd_distance(anchor, $0) + jitter($0, 4.0) }
        orders[anchor] = o
        return o
    }
    var jobs: [(String, Int, String)] = []
    for (name, per) in mix {
        let count = min(mixCap[name] ?? mixMax, max(per <= 1500 ? 1 : 0, Int(area / per)))
        jobs += (0..<count).map { (name, $0, rank(key, [name, $0])) }
    }
    jobs = jobs.enumerated().sorted { ($0.element.2, $0.offset) < ($1.element.2, $1.offset) }.map(\.element)
    for (name, k, seed) in jobs {
        let square = Double(pick(name, k, 4)) * .pi / 2
        let askew = square + (Double(hex(seed, 4, 8)) / 0xFFFF - 0.5) * 0.4
        guard let place = places[name] else { continue }
        let turn = place.askew ? askew : square
        let anchor = ["yard": yard, "dig": digAt, "frame": near][place.anchor]!
        if let p = find(place.size.0, place.size.1, order: around(anchor), turn: turn * 180 / .pi,
                        clear: place.askew ? 2.5 : 1.2) {
            place.make(b, p, heading + turn, seed)
        }
    }
}

// MARK: Pieces

/// A tower crane: a square lattice mast, the slewing head, the jib along
/// `turn` with its trolley and hook, the counter-jib with its weights, and
/// the ties from the mast's top.
private func crane(_ b: Builder, _ p: P2, _ turn: Double, _ height: Double) {
    let z = Level.ground
    upright(b, p, 0, 4.5, 4.5, z, 0.8, "concrete")
    let base = z + 0.8
    let top = base + height
    let h = mast / 2
    let corners = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { P2(p.x + $0.0 * h, p.y + $0.1 * h) }
    for c in corners { bar(b, v3(c, base), v3(c, top), 0.22, "crane") }
    let rungs = Int(height / 3.0)
    for k in 0...rungs {
        let zk = base + height * Double(k) / Double(rungs)
        for i in 0..<4 {
            let a = corners[i], c = corners[(i + 1) % 4]
            bar(b, v3(a, zk), v3(c, zk), 0.12, "crane")
            if k < rungs {
                let z1 = base + height * Double(k + 1) / Double(rungs)
                let (lo, hi) = k % 2 == 0 ? (a, c) : (c, a)
                bar(b, v3(lo, zk), v3(hi, z1), 0.1, "crane")
            }
        }
    }
    // The head turns on the mast.
    let u = V3(cos(turn), sin(turn), 0)
    let v = V3(-u.y, u.x, 0)
    upright(b, p, turn, 2.6, 2.6, top, 1.4, "crane", bottom: true)
    let cab = v3(p) + u * 0.6 + v * 2.0
    upright(b, P2(cab.x, cab.y), turn, 2.0, 1.4, top + 0.1, 1.8, "cabin_b", bottom: true)
    let glass = cab + u * 1.02
    upright(b, P2(glass.x, glass.y), turn, 0.08, 1.2, top + 0.9, 0.8, "cab_glass")
    let deck = top + 1.4
    // Jib: two lower chords, one upper, zigzag between.
    let root = v3(p, deck)
    let tip = root + u * craneJib
    for side in [-0.6, 0.6] { bar(b, root + v * side, tip + v * side, 0.18, "crane") }
    bar(b, root + V3(0, 0, 1.3), tip + V3(0, 0, 0.4), 0.18, "crane")
    let panels = Int(craneJib / 3.0)
    for k in 0..<panels {
        let a = root + u * (craneJib * Double(k) / Double(panels))
        let c = root + u * (craneJib * Double(k + 1) / Double(panels))
        let riseA = 1.3 - 0.9 * Double(k) / Double(panels)
        let riseC = 1.3 - 0.9 * Double(k + 1) / Double(panels)
        for side in [-0.6, 0.6] {
            let (lo, hi) = k % 2 == 0 ? (a, c) : (c, a)
            let rHi = k % 2 == 0 ? riseC : riseA
            bar(b, lo + v * side, hi + V3(0, 0, rHi), 0.08, "crane")
        }
    }
    // Counter-jib and its weights.
    let back = root - u * craneCounter
    bar(b, root, back, 0.9, "crane")
    let weight = root - u * (craneCounter - 1.4)
    upright(b, P2(weight.x, weight.y), turn, 2.2, 2.4, deck - 1.6, 2.0, "concrete", bottom: true)
    // The mast's top and its ties.
    let peak = root + V3(0, 0, 7.0)
    for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
        bar(b, root + V3(sx * 0.6, sy * 0.6, 0.45), peak, 0.16, "crane")
    }
    bar(b, peak, root + u * (craneJib * 0.65) + V3(0, 0, 1.0), 0.07, "crane")
    bar(b, peak, back + V3(0, 0, 0.45), 0.07, "crane")
    // Trolley, cable, hook.
    let reach = root + u * (craneJib * 0.55)
    upright(b, P2(reach.x, reach.y), turn, 1.2, 1.6, deck - 0.5, 0.5, "machine_dark", bottom: true)
    let hookZ = Level.ground + height * 0.45
    bar(b, V3(reach.x, reach.y, deck - 0.5), V3(reach.x, reach.y, hookZ + 0.8), 0.06, "machine_dark")
    upright(b, P2(reach.x, reach.y), turn, 0.7, 0.7, hookZ, 0.8, "machine", bottom: true)
}

/// A tracked excavator: two tracks, the turning body with its cab and
/// counterweight, the boom and stick, the bucket on the ground.
private func excavator(_ b: Builder, _ p: P2, _ heading: Double, _ slew: Double) {
    let z = Level.ground
    let u = V3(cos(heading), sin(heading), 0)
    let v = V3(-u.y, u.x, 0)
    let c = v3(p)
    for side in [-1.2, 1.2] {
        let t = c + v * side
        upright(b, P2(t.x, t.y), heading, 4.2, 0.8, z, 0.9, "machine_dark")
    }
    upright(b, p, heading, 2.0, 1.6, z + 0.2, 0.9, "machine_dark", top: false)
    let turn = heading + slew
    let bu = V3(cos(turn), sin(turn), 0)
    let bv = V3(-bu.y, bu.x, 0)
    upright(b, p, turn, 3.6, 2.6, z + 1.1, 1.1, "machine", bottom: true)
    let weight = c - bu * 1.5
    upright(b, P2(weight.x, weight.y), turn, 0.8, 2.6, z + 2.2, 0.5, "machine")
    let cab = c + bu * 0.9 + bv * 0.65
    upright(b, P2(cab.x, cab.y), turn, 1.4, 1.1, z + 2.2, 1.4, "cab_glass", top: false)
    upright(b, P2(cab.x, cab.y), turn, 1.5, 1.2, z + 3.6, 0.14, "machine", bottom: true)
    let pivot = c + bu * 1.6 - bv * 0.4 + V3(0, 0, z + 1.9)
    let elbow = c + bu * 4.4 - bv * 0.4 + V3(0, 0, z + 4.6)
    let wrist = c + bu * 6.2 - bv * 0.4 + V3(0, 0, z + 1.2)
    bar(b, pivot, elbow, 0.5, "machine")
    bar(b, elbow, wrist, 0.38, "machine")
    upright(b, P2(wrist.x, wrist.y), turn, 0.9, 1.0, z, 0.9, "machine_dark")
}

/// Site cabins: two side by side, one more on the first, each with a window
/// on both long sides.
private func cabins(_ b: Builder, _ p: P2, _ heading: Double, _ seed: String) {
    let z = Level.ground
    let (_, v) = frameAxes(heading)
    let c = v3(p)
    let colours = hex(seed, 0, 2) % 2 == 1 ? ("cabin", "cabin_b") : ("cabin_b", "cabin")
    let spots = [(c - v * 0.9, z, colours.0), (c + v * 0.9, z, colours.1), (c - v * 0.9, z + 2.6, colours.1)]
    for (k, (at, z0, colour)) in spots.enumerated() {
        upright(b, P2(at.x, at.y), heading, 6.0, 1.7, z0, 2.6, colour, top: k != 0)
        for side in [-1.0, 1.0] {
            let w = at + v * (side * 0.87)
            upright(b, P2(w.x, w.y), heading, 1.4, 0.06, z0 + 1.1, 0.9, "cab_glass")
        }
    }
}

/// A face's palette name by where it looks: its side of the sun, the lit
/// tone looking up (or `top`), the shade looking down.
private func sided(_ colour: String, _ top: String? = nil) -> (V3) -> String {
    { n in
        let family = top != nil && n.z > 0.97 ? top! : colour
        let side = n.z < -0.5 ? "shade" : abs(n.z) < 0.97 ? Palette.side(n.x, n.y) : "lit"
        return "\(family).\(side)"
    }
}

/// A face lying on the ground, which nothing will see.
private func onGround(_ points: [V3]) -> Bool { points.allSatisfy { abs($0.z - Level.ground) < 1e-3 } }

/// The rotation turning +Z onto `axis` the shortest way.
private func rotationTo(_ axis: V3) -> simd_double3x3 {
    let a = axis.normalized
    let c = a.z
    if c > 1 - 1e-9 { return matrix_identity_double3x3 }
    if c < -1 + 1e-9 { return simd_double3x3(rows: [V3(1, 0, 0), V3(0, -1, 0), V3(0, 0, -1)]) }
    // Rodrigues about k = z × a.
    let k = V3(-a.y, a.x, 0).normalized
    let s = (1 - c * c).squareRoot()
    let t = 1 - c
    return simd_double3x3(rows: [
        V3(c + k.x * k.x * t, k.x * k.y * t - k.z * s, k.x * k.z * t + k.y * s),
        V3(k.y * k.x * t + k.z * s, c + k.y * k.y * t, k.y * k.z * t - k.x * s),
        V3(k.z * k.x * t - k.y * s, k.z * k.y * t + k.x * s, c + k.z * k.z * t),
    ])
}

/// A cylinder (a cone if radius2 is given) along `axis` around `centre`,
/// capped.
private func cylinder(_ b: Builder, _ centre: V3, _ axis: V3, _ radius: Double, _ length: Double, _ colour: String,
                      segments: Int = 8, radius2: Double? = nil, top: String? = nil) {
    let faces = cone(segments: segments, radius1: radius, radius2: radius2 ?? radius, depth: length, capEnds: true)
    let turn = rotationTo(axis)
    b.instance(faces, { turn * $0 + centre }, sided(colour, top), kind, drop: onGround)
}

/// A pile of sand or gravel: a cone of seven sides.
private func pile(_ b: Builder, _ p: P2, _ colour: String, _ radius: Double, _ height: Double) {
    cylinder(b, v3(p, Level.ground + height / 2), V3(0, 0, 1), radius, height, colour, segments: 7, radius2: 0.0)
}

/// A long mound of dug earth with a flat top, along `heading`.
private func mound(_ b: Builder, _ p: P2, _ heading: Double, _ radius: Double, _ height: Double) {
    let faces = cone(segments: 8, radius1: radius, radius2: radius * 0.35, depth: height, capEnds: true)
    let (u, v) = frameAxes(heading)
    let m = simd_double3x3(rows: [V3(u.x * 1.5, v.x, 0), V3(u.y * 1.5, v.y, 0), V3(0, 0, 1)])
    let centre = v3(p, Level.ground + height / 2)
    b.instance(faces, { m * $0 + centre }, sided("soil"), kind, drop: onGround)
}

/// The concrete frame of the house being built: a foundation slab, columns
/// on a grid of about six metres, a floor slab on every storey, and the top
/// storey half up, its columns standing free.
private func carcass(_ b: Builder, _ p: P2, _ heading: Double, _ lx: Double, _ ly: Double, _ floors: Int) {
    let z = Level.ground
    let (u, v) = frameAxes(heading)
    let c = v3(p)
    upright(b, p, heading, lx + 0.6, ly + 0.6, z, 0.5, "concrete")
    let nx = max(2, pyRound(lx / 6) + 1), ny = max(2, pyRound(ly / 6) + 1)
    for f in 0..<floors {
        let base = z + 0.5 + Double(f) * 3.2
        let last = f == floors - 1
        for i in 0..<nx {
            for j in 0..<ny {
                if last && (i + j) % 2 == 1 { continue }
                let at = c + u * (-lx / 2 + 0.3 + Double(i) * (lx - 0.6) / Double(nx - 1))
                    + v * (-ly / 2 + 0.3 + Double(j) * (ly - 0.6) / Double(ny - 1))
                upright(b, P2(at.x, at.y), heading, 0.5, 0.5, base, 2.9, "concrete", top: last)
            }
        }
        if !last { upright(b, p, heading, lx, ly, base + 2.9, 0.3, "concrete", bottom: true) }
    }
}

/// Three portable toilets in a row, blue with a white roof.
private func toilets(_ b: Builder, _ p: P2, _ heading: Double) {
    let (u, _) = frameAxes(heading)
    for k in [-1.0, 0, 1] {
        let at = v3(p) + u * (k * 1.4)
        upright(b, P2(at.x, at.y), heading, 1.2, 1.2, Level.ground, 2.2, "cabin", top: false)
        upright(b, P2(at.x, at.y), heading, 1.32, 1.32, Level.ground + 2.2, 0.12, "cabin_b", bottom: true)
    }
}

/// The chassis of a truck eight metres long: wheels on `axles` (along the
/// truck from its middle), the frame, the cab at the front with its
/// windscreen. Returns the axes and the middle on the ground.
private func truck(_ b: Builder, _ p: P2, _ heading: Double, _ axles: [Double]) -> (V3, V3, V3) {
    let z = Level.ground
    let (u, v) = frameAxes(heading)
    let c = v3(p, z)
    for x in axles {
        for side in [-1.05, 1.05] {
            cylinder(b, c + u * x + v * side + V3(0, 0, 0.55), v, 0.55, 0.4, "machine_dark", segments: 7)
        }
    }
    upright(b, p, heading, 7.6, 1.8, z + 0.6, 0.4, "machine_dark", bottom: true)
    let cab = c + u * 3.0
    upright(b, P2(cab.x, cab.y), heading, 1.6, 2.3, z + 1.0, 1.9, "machine")
    let glass = c + u * 3.81
    upright(b, P2(glass.x, glass.y), heading, 0.06, 2.0, z + 2.0, 0.7, "cab_glass")
    return (u, v, c)
}

/// A dump truck, its body full of earth heaped over the top.
private func dumpTruck(_ b: Builder, _ p: P2, _ heading: Double) {
    let (u, _, c) = truck(b, p, heading, [-2.6, -1.3, 2.6])
    let body = c - u * 0.95
    upright(b, P2(body.x, body.y), heading, 5.6, 2.4, c.z + 1.0, 1.4, "crane", top: false)
    upright(b, P2(body.x, body.y), heading, 5.3, 2.1, c.z + 1.0, 1.6, "soil")
}

/// A concrete mixer truck, its drum tilted up to the back.
private func mixer(_ b: Builder, _ p: P2, _ heading: Double) {
    let (u, _, c) = truck(b, p, heading, [-2.6, -1.3, 2.6])
    let tilt = 14.0 * .pi / 180
    let axis = -u * cos(tilt) + V3(0, 0, sin(tilt))
    cylinder(b, c - u * 0.9 + V3(0, 0, 2.35), axis, 1.2, 4.2, "cabin_b", radius2: 0.6)
}

/// A bulldozer: tracks, the body, the cab, the blade in front.
private func bulldozer(_ b: Builder, _ p: P2, _ heading: Double) {
    let z = Level.ground
    let (u, v) = frameAxes(heading)
    let c = v3(p)
    for side in [-1.1, 1.1] {
        let t = c + v * side
        upright(b, P2(t.x, t.y), heading, 3.6, 0.7, z, 0.8, "machine_dark")
    }
    let body = c - u * 0.2
    upright(b, P2(body.x, body.y), heading, 2.8, 1.6, z + 0.8, 1.1, "crane", bottom: true)
    let cab = c - u * 0.7
    upright(b, P2(cab.x, cab.y), heading, 1.3, 1.4, z + 1.9, 1.2, "cab_glass", top: false)
    upright(b, P2(cab.x, cab.y), heading, 1.4, 1.5, z + 3.1, 0.14, "crane", bottom: true)
    let blade = c + u * 2.3
    upright(b, P2(blade.x, blade.y), heading, 0.3, 3.4, z, 1.2, "crane")
    for side in [-0.7, 0.7] {
        let a = c + u * 1.1 + v * side + V3(0, 0, z + 1.0)
        bar(b, a, blade - u * 0.15 + v * side + V3(0, 0, z + 0.6), 0.2, "machine_dark")
    }
}

/// A stack of concrete slabs, each laid a little askew.
private func slabs(_ b: Builder, _ p: P2, _ heading: Double, _ count: Int, _ seed: String) {
    for k in 0..<count {
        let skew = (Double(hex(seed, 2 * k, 2 * k + 2)) / 255 - 0.5) * (8 * .pi / 180)
        upright(b, p, heading + skew, 6.0, 1.5, Level.ground + Double(k) * 0.24, 0.24, "concrete")
    }
}

/// Six pallets of bricks, three by two.
private func bricks(_ b: Builder, _ p: P2, _ heading: Double) {
    let (u, v) = frameAxes(heading)
    for i in [-1.0, 0, 1] {
        for j in [-0.6, 0.6] {
            let at = v3(p) + u * (i * 1.3) + v * j
            upright(b, P2(at.x, at.y), heading, 1.2, 1.0, Level.ground, 0.15, "pallet")
            upright(b, P2(at.x, at.y), heading, 1.1, 0.9, Level.ground + 0.15, 0.85, "brick")
        }
    }
}

/// Steel pipes stacked three, two, one.
private func pipes(_ b: Builder, _ p: P2, _ heading: Double) {
    let (u, v) = frameAxes(heading)
    let r = 0.32
    for (count, z) in [(3, r), (2, r * 2.7), (1, r * 4.4)] {
        for k in 0..<count {
            let at = v3(p, Level.ground + z) + v * ((Double(k) - Double(count - 1) / 2) * r * 2.05)
            cylinder(b, at, u, r, 6.0, "pipe", segments: 6)
        }
    }
}

/// Concrete well rings standing in a row, dark inside.
private func rings(_ b: Builder, _ p: P2, _ heading: Double) {
    let (u, _) = frameAxes(heading)
    for k in [-1.0, 0, 1] {
        let at = v3(p, Level.ground + 0.45) + u * (k * 1.65)
        cylinder(b, at, V3(0, 0, 1), 0.75, 0.9, "concrete", segments: 8, top: "machine_dark")
    }
}

// MARK: The mix

/// For each kind: its footprint (along, across), how it is made from a spot,
/// a heading and a seed, where it gathers, and whether it stands square to
/// the site or a little askew.
private struct Place {
    let size: (Double, Double)
    let make: (Builder, P2, Double, String) -> Void
    let anchor: String
    let askew: Bool
}

private let places: [String: Place] = [
    "excavator": Place(size: (9.0, 4.5), make: { b, p, h, seed in
        excavator(b, p, h, Double(hex(seed, 8, 12)) / 0xFFFF * 1.2 - 0.6)
    }, anchor: "dig", askew: true),
    "bulldozer": Place(size: (5.5, 3.6), make: { b, p, h, _ in bulldozer(b, p, h) }, anchor: "dig", askew: true),
    "dump_truck": Place(size: (8.0, 3.0), make: { b, p, h, _ in dumpTruck(b, p, h) }, anchor: "dig", askew: true),
    "soil": Place(size: (15.0, 9.5), make: { b, p, h, seed in
        mound(b, p, h, 4.0 + Double(hex(seed, 8, 10) % 2), 2.4)
    }, anchor: "dig", askew: false),
    "mixer": Place(size: (8.5, 3.0), make: { b, p, h, _ in mixer(b, p, h) }, anchor: "frame", askew: true),
    "sand": Place(size: (6.5, 6.5), make: { b, p, _, _ in pile(b, p, "sand", 3.0, 1.8) }, anchor: "yard", askew: false),
    "gravel": Place(size: (5.5, 5.5), make: { b, p, _, _ in pile(b, p, "gravel", 2.5, 1.4) }, anchor: "yard",
                    askew: false),
    "slabs": Place(size: (6.6, 2.0), make: { b, p, h, seed in
        slabs(b, p, h, 3 + hex(seed, 8, 10) % 4, seed)
    }, anchor: "yard", askew: false),
    "bricks": Place(size: (4.0, 2.6), make: { b, p, h, _ in bricks(b, p, h) }, anchor: "yard", askew: false),
    "pipes": Place(size: (6.6, 2.4), make: { b, p, h, _ in pipes(b, p, h) }, anchor: "yard", askew: false),
    "rings": Place(size: (5.0, 2.0), make: { b, p, h, _ in rings(b, p, h) }, anchor: "yard", askew: false),
]
