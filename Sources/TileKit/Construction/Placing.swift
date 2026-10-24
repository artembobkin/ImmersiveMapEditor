import CryptoKit
import Foundation
import Geometry
import simd

/// Where things go on a site: its frame, the choices fixed by the site, the
/// grid of spots tried from the middle out, and the mix of things.
extension ConstructionSite {
    /// The angle of the site's long side, in degrees.
    static func frame(_ site: Geometry) -> Double {
        let c = site.minimumRotatedRectangle.exterior
        let i = simd_distance(c[1], c[2]) > simd_distance(c[0], c[1]) ? 1 : 0
        return atan2(c[i + 1].y - c[i].y, c[i + 1].x - c[i].x) * 180 / .pi
    }

    /// Python's `round`: halves to even.
    static func pyRound(_ v: Double) -> Int { Int(v.rounded(.toNearestOrEven)) }

    /// The MD5 of the parts as Python's `repr` writes their tuple, in hex: what
    /// fixes a site's choices, the same as the Python build made them.
    static func rank(_ key: (Int, Int), _ parts: [Any]) -> String {
        let items = ["(\(key.0), \(key.1))"] + parts.map { p -> String in
            if let s = p as? String { return "'\(s)'" }
            return "\(p)"
        }
        let text = "(" + items.joined(separator: ", ") + ")"
        return Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The number in hex digits `a..<b` of a rank.
    static func hex(_ s: String, _ a: Int, _ b: Int) -> Int {
        let chars = Array(s)
        return Int(String(chars[a..<b]), radix: 16) ?? 0
    }

    /// Points sorted by a key, ties kept in order, as Python's sort keeps them.
    static func sortedStable(_ pts: [P2], _ key: (P2) -> Double) -> [P2] {
        pts.map { ($0, key($0)) }.enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map { $0.element.0 }
    }

    /// The things of one site, on its `free` ground: the frame of the house
    /// being built with its cranes beside it, cabins and toilets along the
    /// fence, then machines, piles and stacks of materials as many as the
    /// ground holds (one of each kind per so many square metres, `mix`).
    static func furnish(_ b: Builder, _ site: Geometry, _ free: Geometry) {
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

    // MARK: The mix

    /// For each kind: its footprint (along, across), how it is made from a spot,
    /// a heading and a seed, where it gathers, and whether it stands square to
    /// the site or a little askew.
    struct Place {
        let size: (Double, Double)
        let make: (Builder, P2, Double, String) -> Void
        let anchor: String
        let askew: Bool
    }

    static let places: [String: Place] = [
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
}
