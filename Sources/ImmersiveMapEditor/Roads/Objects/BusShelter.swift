import Foundation
import Geometry
import TileKit

/// A bus shelter: where it stands and the way its length runs, the road on
/// its left. It is built at its place (Furniture of TileKit), the roof in
/// plan here.
final class BusShelter: RoadObject {
    var position: Vec2
    /// Degrees counter-clockwise from east.
    var heading: Double

    init(id: String, position: Vec2, heading: Double) {
        self.position = position
        self.heading = heading
        super.init(id: id)
    }

    override class var kindName: String { "Shelter" }
    override class var idLetter: String { "s" }

    override func copy() -> RoadObject { BusShelter(id: id, position: position, heading: heading) }

    /// Its roof in plan.
    var roof: [Vec2] {
        let u = Vec2.fromAngle(heading), v = u.left
        let h = MarkingShapes.shelter / 2
        return [position - u * h.x - v * h.y, position + u * h.x - v * h.y,
                position + u * h.x + v * h.y, position - u * h.x + v * h.y]
    }

    override var outline: [[Vec2]] { [roof] }
    override var anchor: Vec2 { position }

    override func contains(_ p: Vec2, tolerance: Double) -> Bool { winding(roof, p) != 0 }

    override func transform(_ f: (Vec2) -> Vec2, turn: Double, scale: Double) {
        // A shelter keeps its size: it is a thing, not paint.
        position = f(position)
        heading += turn
    }

    override var parameters: [Parameter] { [.number("Heading °", \BusShelter.heading)] }

    override func paint(onRoadway: (Vec2) -> Bool) -> [Paint] {
        let r = roof
        return [Paint(layer: .shelters, ink: .shelter, form: .convex(r)),
                Paint(layer: .shelters, ink: .shelterEdge, form: .outline(r, closed: true, width: 1.5)),
                // The open side, to the road.
                Paint(layer: .shelters, ink: .open, form: .outline([r[3], r[2]], closed: false, width: 3))]
    }

    override func export(into doc: inout RoadDocument, _ ll: (Vec2) -> P2) {
        doc.shelters.append(RoadDocument.Shelter(id: id, position: ll(position), heading: heading))
    }
}
