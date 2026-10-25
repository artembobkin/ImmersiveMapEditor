import Foundation
import Geometry
import TileKit

/// A zebra crossing: its centre, the way the crossing runs (`heading`), its
/// width from kerb to kerb (`span`), its bars' width and length. The
/// pipeline keeps only the bars the roadway holds whole: here the others are
/// red.
final class ZebraMarking: RoadMarking {
    var centre: Vec2
    /// Degrees counter-clockwise from east.
    var heading: Double
    var span: Double
    var bar: Double
    var length: Double

    init(id: String, centre: Vec2, heading: Double, span: Double, bar: Double = Markings.zebraBar,
         length: Double = Markings.zebraWidth) {
        self.centre = centre
        self.heading = heading
        self.span = span
        self.bar = bar
        self.length = length
        super.init(id: id)
    }

    override class var kindName: String { "Zebra" }
    override class var idLetter: String { "z" }
    override class var fileKind: String { "zebra" }

    override func copy() -> RoadObject { ZebraMarking(id: id, centre: centre, heading: heading, span: span, bar: bar, length: length) }

    /// The rectangle it wipes other markings from.
    var zone: [Vec2] {
        let u = Vec2.fromAngle(heading), p = u.left
        let a = span / 2 + 0.5, l = length / 2 + 0.8
        return [centre - p * a - u * l, centre + p * a - u * l, centre + p * a + u * l, centre - p * a + u * l]
    }

    override var outline: [[Vec2]] { [zone] }
    override var anchor: Vec2 { centre }
    override var facing: Double? { heading }

    override func contains(_ p: Vec2, tolerance: Double) -> Bool { winding(zone, p) != 0 }

    override func transform(_ f: (Vec2) -> Vec2, turn: Double, scale: Double) {
        centre = f(centre)
        heading += turn
        // Wider and longer with a scale; a bar stays a bar.
        span = max(1, span * scale)
        length = max(0.5, length * scale)
    }

    override var parameters: [Parameter] {
        [.number("Heading °", \ZebraMarking.heading), .number("Span m", \ZebraMarking.span, minimum: 1),
         .number("Bar m", \ZebraMarking.bar, minimum: 0.1), .number("Length m", \ZebraMarking.length, minimum: 0.5)]
    }

    /// Its bars, each with whether the roadway holds it whole.
    func bars(inside: (Vec2) -> Bool) -> [([Vec2], Bool)] {
        let u = Vec2.fromAngle(heading), p = u.left
        let usable = span - 2 * MarkingShapes.zebraKerb
        let count = Int(((usable + bar) / (2 * bar)).rounded(.down))
        guard count >= 1 else { return [] }
        let first = -Double(count * 2 - 1) * bar / 2 + bar / 2
        return (0..<count).map { k in
            let c = centre + p * (first + Double(k) * 2 * bar)
            let quad = [c - p * (bar / 2) - u * (length / 2), c + p * (bar / 2) - u * (length / 2),
                        c + p * (bar / 2) + u * (length / 2), c - p * (bar / 2) + u * (length / 2)]
            return (quad, quad.allSatisfy(inside))
        }
    }

    override func paint(onRoadway: (Vec2) -> Bool) -> [Paint] {
        bars(inside: onRoadway).map { Paint(layer: .markings, ink: $0.1 ? .white : .wrong, form: .convex($0.0)) }
    }

    override func fill(_ k: inout Mark, _ ll: (Vec2) -> P2) {
        k.centre = ll(centre)
        k.heading = heading
        k.span = span
        k.bar = bar
        k.length = length
    }
}
