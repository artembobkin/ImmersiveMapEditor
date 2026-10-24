import Foundation
import simd

/// The areas' edges sorted into horizontal strips, so a point's winding
/// looks only at the edges its strip crosses.
struct RoadwayIndex {
    static let strip = 5.0
    var revision = -1
    private var strips: [Int: [(a: Vec2, b: Vec2, area: Int)]] = [:]
    private var ops: [String] = []

    init() {}

    init(_ doc: RoadPlan, _ revision: Int) {
        self.revision = revision
        ops = doc.areas.map(\.op)
        for (i, area) in doc.areas.enumerated() {
            for ring in area.rings {
                for k in ring.indices {
                    let a = ring[k], b = ring[(k + 1) % ring.count]
                    let lo = Int((min(a.y, b.y) / Self.strip).rounded(.down))
                    let hi = Int((max(a.y, b.y) / Self.strip).rounded(.down))
                    for s in lo...hi { strips[s, default: []].append((a, b, i)) }
                }
            }
        }
    }

    func onRoadway(_ p: Vec2) -> Bool {
        var w: [Int: Int] = [:]
        for (a, b, i) in strips[Int((p.y / Self.strip).rounded(.down))] ?? [] {
            if a.y <= p.y {
                if b.y > p.y && cross(b - a, p - a) > 0 { w[i, default: 0] += 1 }
            } else if b.y <= p.y && cross(b - a, p - a) < 0 {
                w[i, default: 0] -= 1
            }
        }
        let inside = w.filter { $0.value != 0 }.keys
        return inside.contains { ops[$0] == "add" } && !inside.contains { ops[$0] == "cut" }
    }
}
