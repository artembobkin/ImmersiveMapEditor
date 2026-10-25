import Foundation
import Geometry
import TileKit

/// The yellow zigzag of a bus stop: a baseline of two points along the kerb,
/// the roadway on its `side` (1 left, -1 right), its teeth `step` apart and
/// `depth` deep. Its two points are edited as a line's.
final class ZigzagMarking: RoadMarking {
    var points: [Vec2]
    var side: Int
    var step: Double
    var depth: Double

    init(id: String, points: [Vec2], side: Int = 1, step: Double = Markings.zigzagStep, depth: Double = Markings.zigzagDepth) {
        self.points = points
        self.side = side
        self.step = step
        self.depth = depth
        super.init(id: id)
    }

    override class var kindName: String { "Zigzag" }
    override class var idLetter: String { "g" }
    override class var fileKind: String { "zigzag" }

    override func copy() -> RoadObject { ZigzagMarking(id: id, points: points, side: side, step: step, depth: depth) }

    override var outlineClosed: Bool { false }

    override var rings: [[Vec2]] {
        get { [points] }
        set { points = newValue.first ?? [] }
    }

    /// Its line: from the baseline, the inset into the roadway, out to the
    /// depth and back every step.
    var teeth: [Vec2] {
        guard points.count >= 2 else { return [] }
        let a = points[0], b = points[1]
        let run = (b - a).length
        guard run >= 1 else { return [] }
        let u = (b - a) / run
        let n = u.left * Double(side)
        let steps = max(1, Int((run / step).rounded()))
        return (0...steps).map { k in
            let t = Double(k) * run / Double(steps)
            return a + u * t + n * (MarkingShapes.zigzagInset + (k % 2 == 1 ? depth : 0))
        }
    }

    override var outline: [[Vec2]] { [teeth] }

    override func contains(_ p: Vec2, tolerance: Double) -> Bool {
        let pts = teeth
        return (0..<max(0, pts.count - 1)).contains { (nearestOnSegment(p, pts[$0], pts[$0 + 1]).0 - p).length < tolerance + 0.2 }
    }

    override func transform(_ f: (Vec2) -> Vec2, turn: Double, scale: Double) {
        points = points.map(f)
        step = max(0.5, step * scale)
        depth *= scale
    }

    /// Its teeth to the other side of its baseline.
    func flip() { side *= -1 }

    override var parameters: [Parameter] {
        [.number("Step m", \ZigzagMarking.step, minimum: 0.5), .number("Depth m", \ZigzagMarking.depth),
         .action("Flip side  X") { (z: ZigzagMarking) in z.flip() }]
    }

    override func paint(onRoadway: (Vec2) -> Bool) -> [Paint] {
        MarkingShapes.stroke(teeth, width: MarkingShapes.zigzagLine).map { Paint(layer: .markings, ink: .yellow, form: .convex($0)) }
    }

    override func fill(_ k: inout Mark, _ ll: (Vec2) -> P2) {
        k.side = side
        k.step = step
        k.depth = depth
        k.points = points.map(ll)
    }
}
