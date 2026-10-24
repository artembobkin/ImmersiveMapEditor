import Foundation

/// What build/markings.py makes of a marking's parameters, drawn the same
/// way here: its constants and rules, in Swift.
enum MarkingShapes {
    static let line = 0.15
    static let dash = 3.0, gap = 6.0
    static let double = 0.2
    static let zebraKerb = 0.4
    static let zigzagInset = 0.4
    static let zigzagLine = 0.15
    static let letterSize = Vec2(1.4, 2.6)
    static let shelter = Vec2(4.6, 1.6)
    /// The letter A in a unit box, and the hole of its crossbar.
    static let letterA: [[Vec2]] = [
        [Vec2(0, 0), Vec2(0.23, 0), Vec2(0.32, 0.28), Vec2(0.68, 0.28), Vec2(0.77, 0), Vec2(1, 0),
         Vec2(0.64, 1), Vec2(0.36, 1)],
        [Vec2(0.38, 0.43), Vec2(0.5, 0.78), Vec2(0.62, 0.43)],
    ]

    /// A painted strip along a polyline, as quads, one per segment.
    static func stroke(_ pts: [Vec2], width: Double) -> [[Vec2]] {
        guard pts.count >= 2 else { return [] }
        let side = offsetLine(pts, width / 2), other = offsetLine(pts, -width / 2)
        return (0..<(pts.count - 1)).map { i in [other[i], other[i + 1], side[i + 1], side[i]] }
    }

    /// A line marking: solid, dashed from its first point, or double.
    static func lineQuads(_ m: RoadDocument.Marking) -> [[Vec2]] {
        guard m.points.count >= 2 else { return [] }
        switch m.style {
        case "double":
            return [double, -double].flatMap { stroke(offsetLine(m.points, $0), width: line) }
        case "dashed":
            return dashes(m.points, dash: dash, gap: gap).flatMap { stroke($0, width: line) }
        default:
            return stroke(m.points, width: line)
        }
    }

    /// A zebra's bars, each with whether the roadway holds it whole.
    static func zebraBars(_ m: RoadDocument.Marking, inside: (Vec2) -> Bool) -> [([Vec2], Bool)] {
        let u = Vec2.fromAngle(m.heading), p = u.left
        let usable = m.span - 2 * zebraKerb
        let count = Int(((usable + m.bar) / (2 * m.bar)).rounded(.down))
        guard count >= 1 else { return [] }
        let first = -Double(count * 2 - 1) * m.bar / 2 + m.bar / 2
        return (0..<count).map { k in
            let c = m.centre + p * (first + Double(k) * 2 * m.bar)
            let quad = [c - p * (m.bar / 2) - u * (m.length / 2), c + p * (m.bar / 2) - u * (m.length / 2),
                        c + p * (m.bar / 2) + u * (m.length / 2), c - p * (m.bar / 2) + u * (m.length / 2)]
            return (quad, quad.allSatisfy(inside))
        }
    }

    /// The rectangle a zebra wipes other markings from.
    static func zebraZone(_ m: RoadDocument.Marking) -> [Vec2] {
        let u = Vec2.fromAngle(m.heading), p = u.left
        let a = m.span / 2 + 0.5, l = m.length / 2 + 0.8
        return [m.centre - p * a - u * l, m.centre + p * a - u * l, m.centre + p * a + u * l, m.centre - p * a + u * l]
    }

    /// A zigzag's points: from its baseline, the inset into the roadway,
    /// out to the depth and back every step.
    static func zigzag(_ m: RoadDocument.Marking) -> [Vec2] {
        guard m.points.count >= 2 else { return [] }
        let a = m.points[0], b = m.points[1]
        let run = (b - a).length
        guard run >= 1 else { return [] }
        let u = (b - a) / run
        let n = u.left * Double(m.side)
        let steps = max(1, Int((run / m.step).rounded()))
        return (0...steps).map { k in
            let t = Double(k) * run / Double(steps)
            return a + u * t + n * (zigzagInset + (k % 2 == 1 ? m.depth : 0))
        }
    }

    /// The letter's rings, its top along its heading.
    static func letterRings(_ m: RoadDocument.Marking) -> [[Vec2]] {
        letterA.map { ring in
            ring.map { q in
                let local = Vec2(q.x * letterSize.x - letterSize.x / 2, q.y * letterSize.y - letterSize.y / 2)
                return local.rotated(m.heading - 90) + m.centre
            }
        }
    }

    /// A shelter's roof in plan.
    static func shelterRect(_ s: RoadDocument.Shelter) -> [Vec2] {
        let u = Vec2.fromAngle(s.heading), v = u.left
        let h = shelter / 2
        return [s.position - u * h.x - v * h.y, s.position + u * h.x - v * h.y,
                s.position + u * h.x + v * h.y, s.position - u * h.x + v * h.y]
    }
}
