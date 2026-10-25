import Foundation
import TileKit

/// What TileKit's Markings makes of a marking's parameters, drawn the same
/// way here as quads for Metal: its constants are TileKit's, the rules the
/// same. TileKit builds polygons (GEOS) for the tile, this draws quads fast
/// enough to follow a drag.
enum MarkingShapes {
    static let line = Markings.line
    static let dash = Markings.dash.0, gap = Markings.dash.1
    static let double = Markings.double
    static let zebraKerb = Markings.zebraKerb
    static let zigzagInset = Markings.zigzagInset
    static let zigzagLine = Markings.zigzagLine
    static let letterSize = Vec2(Markings.busLetterSize.0, Markings.busLetterSize.1)
    static let shelter = Vec2(shelterSize.0, shelterSize.1)
    /// The letter A in a unit box, its outer ring turned counter-clockwise
    /// for the stencil, and the hole of its crossbar.
    static let letterA: [[Vec2]] = [Array(Markings.letterA[0].reversed()), Markings.letterA[1]]

    /// A painted strip along a polyline, as quads, one per segment.
    static func stroke(_ pts: [Vec2], width: Double) -> [[Vec2]] {
        guard pts.count >= 2 else { return [] }
        let side = offsetLine(pts, width / 2), other = offsetLine(pts, -width / 2)
        return (0..<(pts.count - 1)).map { i in [other[i], other[i + 1], side[i + 1], side[i]] }
    }

    /// A line marking: solid, dashed from its first point, or double.
    static func lineQuads(_ m: RoadPlan.Marking) -> [[Vec2]] {
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
    static func zebraBars(_ m: RoadPlan.Marking, inside: (Vec2) -> Bool) -> [([Vec2], Bool)] {
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
    static func zebraZone(_ m: RoadPlan.Marking) -> [Vec2] {
        let u = Vec2.fromAngle(m.heading), p = u.left
        let a = m.span / 2 + 0.5, l = m.length / 2 + 0.8
        return [m.centre - p * a - u * l, m.centre + p * a - u * l, m.centre + p * a + u * l, m.centre - p * a + u * l]
    }

    /// A zigzag's points: from its baseline, the inset into the roadway,
    /// out to the depth and back every step.
    static func zigzag(_ m: RoadPlan.Marking) -> [Vec2] {
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
    static func letterRings(_ m: RoadPlan.Marking) -> [[Vec2]] {
        let size = letterSize * (m.size / letterSize.y)
        return letterA.map { ring in
            ring.map { q in
                let local = Vec2(q.x * size.x - size.x / 2, q.y * size.y - size.y / 2)
                return local.rotated(m.heading - 90) + m.centre
            }
        }
    }

    /// A shelter's roof in plan.
    static func shelterRect(_ s: RoadPlan.Shelter) -> [Vec2] {
        let u = Vec2.fromAngle(s.heading), v = u.left
        let h = shelter / 2
        return [s.position - u * h.x - v * h.y, s.position + u * h.x - v * h.y,
                s.position + u * h.x + v * h.y, s.position - u * h.x + v * h.y]
    }
}
