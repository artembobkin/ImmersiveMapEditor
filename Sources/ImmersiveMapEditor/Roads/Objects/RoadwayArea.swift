import Foundation
import Geometry
import TileKit

/// An area of roadway: added to the roadway, or cut out of it. Its rings
/// are the outer one, counter-clockwise, then its holes, clockwise. The
/// added ones get the kerb band around them.
final class RoadwayArea: RoadObject {
    /// "add" or "cut".
    var op: String
    private var points: [[Vec2]]

    init(id: String, op: String, rings: [[Vec2]]) {
        self.op = op
        points = rings
        super.init(id: id)
    }

    override class var kindName: String { "Area" }
    override class var idLetter: String { "a" }
    override var title: String { "\(op == "add" ? "Roadway" : "Cut") \(id): \(points.count - 1) holes, \(points.reduce(0) { $0 + $1.count }) points" }

    override func copy() -> RoadObject { RoadwayArea(id: id, op: op, rings: points) }

    override var rings: [[Vec2]] {
        get { points }
        set { points = newValue }
    }
    override var closedRings: Bool { true }
    override var minimumPoints: Int { 3 }
    override var takesNewPoints: Bool { true }
    /// Its outer ring alone frames it.
    override var outline: [[Vec2]] { points }

    /// Inside: the rings' winding, holes left out.
    override func contains(_ p: Vec2, tolerance: Double) -> Bool {
        points.reduce(0) { $0 + winding($1, p) } != 0
    }

    override var parameters: [Parameter] {
        [.choice("Op", \RoadwayArea.op, [("Add roadway", "add"), ("Cut roadway", "cut")])]
    }

    override func paint(onRoadway: (Vec2) -> Bool) -> [Paint] {
        if op == "add" {
            var out = [Paint(layer: .roadway, ink: .asphalt, form: .rings(points))]
            for ring in points {
                for i in ring.indices {
                    out.append(Paint(layer: .roadway, ink: .kerb, form: .band(ring[i], ring[(i + 1) % ring.count], width: 0.7)))
                }
            }
            return out
        }
        return [Paint(layer: .cuts, ink: .ground, form: .rings(points))]
            + points.map { Paint(layer: .cuts, ink: .cutEdge, form: .outline($0, closed: true, width: 1.5)) }
    }

    override func export(into doc: inout RoadDocument, _ ll: (Vec2) -> P2) {
        doc.areas.append(RoadDocument.Area(id: id, op: op, outer: points[0].map(ll), holes: points.dropFirst().map { $0.map(ll) }))
    }
}
