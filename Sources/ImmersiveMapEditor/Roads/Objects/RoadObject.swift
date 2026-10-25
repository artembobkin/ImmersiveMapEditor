import Foundation
import Geometry
import TileKit

/// Anything of a road document the Roads view edits: a roadway area, a
/// marking (a line, a zebra, a zigzag, a letter), a bus shelter. Each kind
/// is a subclass that says, for itself, how it is drawn (`paint`), picked
/// (`contains`), framed (`outline`), moved, turned and scaled
/// (`transform`), which of its points can be edited (`rings`), what the
/// panel edits of it (`parameters`) and how the file keeps it (`export`).
/// Nothing outside asks an object what kind it is.
///
/// Objects are references: a plan is copied whole (`RoadPlan.copy`) before
/// a change, so an undo step keeps the objects as they were and nothing is
/// ever changed in place outside a change.
class RoadObject {
    var id: String

    init(id: String) { self.id = id }

    /// The kind's name, for the panel and for undo ("Zebra").
    class var kindName: String { "Object" }
    /// The letter of the kind's ids in the file ("z" for z12).
    class var idLetter: String { "o" }

    var title: String { "\(type(of: self).kindName) \(id)" }

    /// A copy of its own, for a plan's copy.
    func copy() -> RoadObject { fatalError("\(type(of: self)) does not copy itself") }

    // MARK: Points

    /// The points one edits point by point: an area's rings (the outer one
    /// first), a line's or a zigzag's points as one ring. None for the rest.
    var rings: [[Vec2]] {
        get { [] }
        set {}
    }
    /// Whether its rings close on themselves.
    var closedRings: Bool { false }
    /// The fewest points a ring keeps: fewer and the object goes.
    var minimumPoints: Int { 2 }
    /// Whether a double-click on its edge adds a point.
    var takesNewPoints: Bool { false }

    // MARK: Shape

    /// Its shape as drawn, for the selection's outline and frame.
    var outline: [[Vec2]] { rings }
    /// Whether its outline closes on itself (an area, a zebra), or runs
    /// open (a line).
    var outlineClosed: Bool { true }
    /// Where it is: the middle of its outline.
    var anchor: Vec2 {
        let pts = outline.flatMap { $0 }
        return pts.isEmpty ? .zero : pts.reduce(.zero, +) / Double(pts.count)
    }
    /// The way it faces, drawn as a tick from its anchor, when it has one.
    var facing: Double? { nil }

    /// Whether a click at `p` (within `tolerance` metres) takes it.
    func contains(_ p: Vec2, tolerance: Double) -> Bool { false }

    // MARK: Changes

    /// Moves its points by `f`, turns what it faces by `turn` degrees and
    /// scales its sizes by `scale`: a move, a turn about a pivot, a scale.
    func transform(_ f: (Vec2) -> Vec2, turn: Double, scale: Double) {
        rings = rings.map { $0.map(f) }
    }

    /// Turns it about itself.
    func turn(by degrees: Double) {
        let c = anchor
        transform({ $0.rotated(degrees, around: c) }, turn: degrees, scale: 1)
    }

    /// What the panel edits of it.
    var parameters: [Parameter] { [] }

    // MARK: Drawing and the file

    /// What it paints in the Roads view; `onRoadway` tells where the
    /// roadway is.
    func paint(onRoadway: (Vec2) -> Bool) -> [Paint] { [] }

    /// Adds itself to the file's document, its points turned into longitude
    /// and latitude by `ll`.
    func export(into doc: inout RoadDocument, _ ll: (Vec2) -> P2) {}
}

/// One thing the panel edits of an object: a number, a choice among
/// values, or an action. It reads and writes whatever object it is given,
/// of its kind: the copy a change makes, not the object shown.
struct Parameter: Identifiable {
    enum Control {
        case number(minimum: Double?, get: (RoadObject) -> Double, set: (RoadObject, Double) -> Void)
        case choice(options: [(title: String, value: String)], get: (RoadObject) -> String, set: (RoadObject, String) -> Void)
        case action((RoadObject) -> Void)
    }

    let label: String
    let control: Control
    var id: String { label }

    static func number<T: RoadObject>(_ label: String, _ key: ReferenceWritableKeyPath<T, Double>,
                                      minimum: Double? = nil) -> Parameter {
        Parameter(label: label, control: .number(minimum: minimum, get: { ($0 as? T)?[keyPath: key] ?? 0 },
                                                  set: { o, v in (o as? T)?[keyPath: key] = minimum.map { max($0, v) } ?? v }))
    }

    static func choice<T: RoadObject>(_ label: String, _ key: ReferenceWritableKeyPath<T, String>,
                                      _ options: [(title: String, value: String)]) -> Parameter {
        Parameter(label: label, control: .choice(options: options, get: { ($0 as? T)?[keyPath: key] ?? "" },
                                                 set: { o, v in (o as? T)?[keyPath: key] = v }))
    }

    static func action<T: RoadObject>(_ label: String, _ body: @escaping (T) -> Void) -> Parameter {
        Parameter(label: label, control: .action { o in if let o = o as? T { body(o) } })
    }
}

/// What an object paints, in plan: the renderer (RoadLayers) turns it into
/// meshes, in the layers' order, so objects say what they are made of and
/// never how Metal draws it.
struct Paint {
    enum Layer { case roadway, cuts, markings, shelters }
    enum Ink { case asphalt, kerb, ground, cutEdge, white, yellow, wrong, shelter, shelterEdge, open }
    enum Form {
        /// Filled rings, non-zero winding: holes wound the other way.
        case rings([[Vec2]])
        /// A filled convex polygon (a quad).
        case convex([Vec2])
        /// A strip `width` metres wide from a to b.
        case band(Vec2, Vec2, width: Double)
        /// A line on screen, `width` pixels wide whatever the zoom.
        case outline([Vec2], closed: Bool, width: Float)
    }

    let layer: Layer
    let ink: Ink
    let form: Form
}
