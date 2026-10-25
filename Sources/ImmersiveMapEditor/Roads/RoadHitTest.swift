import Foundation
import simd

/// What lies under a point of the Roads view: the points, objects and edges
/// of the plan, within `tolerance` metres, each object answering for its
/// own shape. Points are pickable on every ring when handles show, else
/// only on what is selected, and only those in `limit` (the working tile):
/// a view works on its one tile.
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

    /// The rings whose points can be picked: their object's id, the ring's
    /// place, its points.
    func pickable() -> [(String, Int, [Vec2])] {
        let owners = Set(selection.map { item -> String in
            switch item {
            case .vertex(let o, _, _): o
            case .object(let o): o
            }
        })
        var out: [(String, Int, [Vec2])] = []
        for o in doc.objects where handlesShown || owners.contains(o.id) {
            if o is RoadMarking && !markingsShown { continue }
            for (r, ring) in o.rings.enumerated() { out.append((o.id, r, ring)) }
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

    /// The topmost marking or shelter under the point. An area is not taken
    /// so: a click on the roadway must not pick up the whole network.
    func object(_ p: Vec2) -> Item? {
        doc.objects.reversed().first { o in
            !(o is RoadwayArea) && (markingsShown || !(o is RoadMarking)) && o.contains(p, tolerance: tolerance)
        }.map { .object($0.id) }
    }

    /// The topmost area under the point.
    func area(_ p: Vec2) -> Item? {
        doc.areas.reversed().first { $0.contains(p, tolerance: tolerance) }.map { .object($0.id) }
    }

    /// The nearest edge of an object that takes new points, within reach:
    /// its owner, ring, the index of its first point, the nearest point.
    func edge(_ p: Vec2) -> (String, Int, Int, Vec2)? {
        var best: (Double, (String, Int, Int, Vec2))?
        for o in doc.objects where o.takesNewPoints {
            for (r, pts) in o.rings.enumerated() {
                let n = pts.count
                for i in 0..<(o.closedRings ? n : max(0, n - 1)) {
                    let (q, _) = nearestOnSegment(p, pts[i], pts[(i + 1) % n])
                    let d = (q - p).length
                    if d < tolerance && d < (best?.0 ?? .infinity) { best = (d, (o.id, r, i, q)) }
                }
            }
        }
        return best?.1
    }

    /// Everything in the box a..b: the points of the rings shown, and the
    /// objects without points (zebras, letters, shelters) by where they are.
    func box(_ a: Vec2, _ b: Vec2) -> Set<Item> {
        let lo = simd_min(a, b), hi = simd_max(a, b)
        func inside(_ p: Vec2) -> Bool { p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y && within(p) }
        var picked: Set<Item> = []
        for (owner, ring, pts) in pickable() {
            for (i, q) in pts.enumerated() where inside(q) { picked.insert(.vertex(owner, ring: ring, index: i)) }
        }
        for o in doc.objects where o.rings.isEmpty && (markingsShown || !(o is RoadMarking)) && inside(o.anchor) {
            picked.insert(.object(o.id))
        }
        return picked
    }
}
