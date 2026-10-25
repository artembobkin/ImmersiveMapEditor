import Foundation
import Geometry
import TileKit

/// A line painted along points: solid, dashed from its first point, or
/// double; white or yellow. Its points are edited one by one.
final class LineMarking: RoadMarking {
    /// "solid", "dashed" or "double".
    var style: String
    /// "white" or "yellow".
    var colour: String
    var points: [Vec2]

    init(id: String, style: String = "dashed", colour: String = "white", points: [Vec2]) {
        self.style = style
        self.colour = colour
        self.points = points
        super.init(id: id)
    }

    override class var kindName: String { "Line" }
    override class var idLetter: String { "m" }
    override class var fileKind: String { "line" }

    override func copy() -> RoadObject { LineMarking(id: id, style: style, colour: colour, points: points) }

    override var outlineClosed: Bool { false }

    override var rings: [[Vec2]] {
        get { [points] }
        set { points = newValue.first ?? [] }
    }
    override var takesNewPoints: Bool { true }

    override func contains(_ p: Vec2, tolerance: Double) -> Bool {
        (0..<max(0, points.count - 1)).contains { (nearestOnSegment(p, points[$0], points[$0 + 1]).0 - p).length < tolerance + 0.2 }
    }

    override var parameters: [Parameter] {
        [.choice("Style", \LineMarking.style, [("Solid", "solid"), ("Dashed", "dashed"), ("Double", "double")]),
         .choice("Colour", \LineMarking.colour, [("White", "white"), ("Yellow", "yellow")])]
    }

    /// Its paint: solid, dashed from its first point, or double.
    var quads: [[Vec2]] {
        guard points.count >= 2 else { return [] }
        switch style {
        case "double":
            return [MarkingShapes.double, -MarkingShapes.double].flatMap {
                MarkingShapes.stroke(offsetLine(points, $0), width: MarkingShapes.line)
            }
        case "dashed":
            return dashes(points, dash: MarkingShapes.dash, gap: MarkingShapes.gap).flatMap { MarkingShapes.stroke($0, width: MarkingShapes.line) }
        default:
            return MarkingShapes.stroke(points, width: MarkingShapes.line)
        }
    }

    override func paint(onRoadway: (Vec2) -> Bool) -> [Paint] {
        quads.map { Paint(layer: .markings, ink: colour == "yellow" ? .yellow : .white, form: .convex($0)) }
    }

    override func fill(_ k: inout Mark, _ ll: (Vec2) -> P2) {
        k.style = style
        k.colour = colour
        k.points = points.map(ll)
    }
}
