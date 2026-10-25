import Foundation
import Geometry
import TileKit

/// A letter painted on a bus lane (the letter A): its centre, the way its
/// top points (`heading`), its height in metres (its width in proportion).
final class LetterMarking: RoadMarking {
    var text: String
    var centre: Vec2
    /// Degrees counter-clockwise from east: where its top points.
    var heading: Double
    var size: Double

    init(id: String, text: String = "A", centre: Vec2, heading: Double, size: Double = Markings.busLetterSize.1) {
        self.text = text
        self.centre = centre
        self.heading = heading
        self.size = size
        super.init(id: id)
    }

    override class var kindName: String { "Letter" }
    override class var idLetter: String { "l" }
    override class var fileKind: String { "letter" }

    override func copy() -> RoadObject { LetterMarking(id: id, text: text, centre: centre, heading: heading, size: size) }

    /// Its rings: the letter's outline and its crossbar's hole, its top
    /// along its heading.
    var letterRings: [[Vec2]] {
        let box = MarkingShapes.letterSize * (size / MarkingShapes.letterSize.y)
        return MarkingShapes.letterA.map { ring in
            ring.map { q in Vec2(q.x * box.x - box.x / 2, q.y * box.y - box.y / 2).rotated(heading - 90) + centre }
        }
    }

    override var outline: [[Vec2]] { letterRings }
    override var anchor: Vec2 { centre }
    override var facing: Double? { heading }

    override func contains(_ p: Vec2, tolerance: Double) -> Bool {
        (centre - p).length < 1.6 * size / MarkingShapes.letterSize.y + tolerance
    }

    override func transform(_ f: (Vec2) -> Vec2, turn: Double, scale: Double) {
        centre = f(centre)
        heading += turn
        size = max(0.3, size * scale)
    }

    override var parameters: [Parameter] {
        [.number("Heading °", \LetterMarking.heading), .number("Size m", \LetterMarking.size, minimum: 0.3)]
    }

    override func paint(onRoadway: (Vec2) -> Bool) -> [Paint] {
        [Paint(layer: .markings, ink: .white, form: .rings(letterRings))]
    }

    override func fill(_ k: inout Mark, _ ll: (Vec2) -> P2) {
        k.text = text
        k.centre = ll(centre)
        k.heading = heading
        k.size = size
    }
}
