import Foundation

/// What lies under a point of the Roads view: the points, markings,
/// shelters, edges and areas of the document, within `tolerance` metres.
/// Points are pickable on every ring and line when handles show, else only
/// on what is selected, and only those in `limit` (the working tile): a
/// view works on its one tile.
struct RoadHitTest {
    let doc: RoadPlan
    let selection: Set<Item>
    let tolerance: Double
    let handlesShown: Bool
    let markingsShown: Bool
    var limit: (Vec2, Vec2)?

    /// Whether a point lies in the tile worked on.
    func within(_ p: Vec2) -> Bool {
        guard let (lo, hi) = limit else { return true }
        return p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y
    }

    /// The rings and lines whose points can be picked.
    func pickable() -> [(Owner, Int, [Vec2])] {
        let owners = Set(selection.compactMap { item -> Owner? in
            switch item {
            case .vertex(let o, _, _): o
            case .area(let a): .area(a)
            case .marking(let m): .marking(m)
            default: nil
            }
        })
        var out: [(Owner, Int, [Vec2])] = []
        for (i, a) in doc.areas.enumerated() where handlesShown || owners.contains(.area(i)) {
            for (r, ring) in a.rings.enumerated() { out.append((.area(i), r, ring)) }
        }
        for (i, m) in doc.markings.enumerated() where !m.points.isEmpty && (handlesShown || owners.contains(.marking(i))) {
            out.append((.marking(i), 0, m.points))
        }
        return out
    }

    func vertex(_ p: Vec2) -> Item? {
        var best: (Double, Item)?
        for (owner, ring, pts) in pickable() {
            for (i, q) in pts.enumerated() where within(q) {
                let d = (q - p).length
                if d < tolerance && d < (best?.0 ?? .infinity) { best = (d, .vertex(owner, ring: ring, index: i)) }
            }
        }
        return best?.1
    }

    func marking(_ p: Vec2) -> Item? {
        guard markingsShown else { return nil }
        for (i, m) in doc.markings.enumerated().reversed() {
            switch m.kind {
            case "zebra":
                if winding(MarkingShapes.zebraZone(m), p) != 0 { return .marking(i) }
            case "letter":
                if (m.centre - p).length < 1.6 * m.size / MarkingShapes.letterSize.y + tolerance { return .marking(i) }
            default:
                let pts = m.kind == "zigzag" ? MarkingShapes.zigzag(m) : m.points
                for k in 0..<max(0, pts.count - 1) where (nearestOnSegment(p, pts[k], pts[k + 1]).0 - p).length < tolerance + 0.2 {
                    return .marking(i)
                }
            }
        }
        return nil
    }

    func shelter(_ p: Vec2) -> Item? {
        doc.shelters.indices.reversed().first { winding(MarkingShapes.shelterRect(doc.shelters[$0]), p) != 0 }.map { .shelter($0) }
    }

    /// The nearest edge of an area or a line within reach: its ring, the
    /// index of its first point and the nearest point on it.
    func edge(_ p: Vec2) -> (Owner, Int, Int, Vec2)? {
        var best: (Double, (Owner, Int, Int, Vec2))?
        func scan(_ owner: Owner, _ ring: Int, _ pts: [Vec2], closed: Bool) {
            let n = pts.count
            for i in 0..<(closed ? n : n - 1) {
                let (q, _) = nearestOnSegment(p, pts[i], pts[(i + 1) % n])
                let d = (q - p).length
                if d < tolerance && d < (best?.0 ?? .infinity) { best = (d, (owner, ring, i, q)) }
            }
        }
        for (i, a) in doc.areas.enumerated() {
            for (r, ring) in a.rings.enumerated() { scan(.area(i), r, ring, closed: true) }
        }
        for (i, m) in doc.markings.enumerated() where m.kind == "line" { scan(.marking(i), 0, m.points, closed: false) }
        return best?.1
    }

    func area(_ p: Vec2) -> Item? {
        doc.areas.indices.reversed().first { a in doc.areas[a].rings.reduce(0) { $0 + winding($1, p) } != 0 }.map { .area($0) }
    }

    /// Everything with its point in the box a..b.
    func box(_ a: Vec2, _ b: Vec2) -> Set<Item> {
        let lo = simd_min(a, b), hi = simd_max(a, b)
        func inside(_ p: Vec2) -> Bool { p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y && within(p) }
        var picked: Set<Item> = []
        for (owner, ring, pts) in pickable() {
            for (i, q) in pts.enumerated() where inside(q) { picked.insert(.vertex(owner, ring: ring, index: i)) }
        }
        for (i, m) in doc.markings.enumerated() where m.points.isEmpty && inside(m.centre) { picked.insert(.marking(i)) }
        for (i, s) in doc.shelters.enumerated() where inside(s.position) { picked.insert(.shelter(i)) }
        return picked
    }
}

import simd
