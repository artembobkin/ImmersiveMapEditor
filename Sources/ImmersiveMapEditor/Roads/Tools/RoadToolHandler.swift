import Foundation
import Geometry

/// The pointer as a tool sees it: where (in metres), how many clicks, the
/// modifier keys. No AppKit: the view translates its events into this.
struct Pointer {
    var at: Vec2
    var clicks = 1
    var shift = false
    var option = false
    var command = false
}

/// What a tool shows while it works, drawn by the view's overlay.
enum ToolPreview {
    case none
    /// Points clicked so far, closed into a ring or not, and the pointer.
    case draft([Vec2], closed: Bool, pointer: Vec2?)
    case box(Vec2, Vec2)
    case line(Vec2, Vec2)
}

/// What a tool needs of the editor and the view: the editor to change, what
/// is under a point, how many metres a few screen points are.
@MainActor
struct ToolContext {
    let editor: RoadEditor
    let hits: RoadHitTest
    var tolerance: Double { hits.tolerance }
}

/// One tool of the Roads view. A new tool is a new type: the view does not
/// change. Every method has a default that does nothing.
@MainActor
protocol RoadToolHandler: AnyObject {
    func down(_ p: Pointer, _ ctx: ToolContext)
    func drag(_ p: Pointer, _ ctx: ToolContext)
    func up(_ p: Pointer, _ ctx: ToolContext)
    func hover(_ at: Vec2)
    /// Return: finish what is being drawn. False if there is nothing to finish.
    func commit(_ ctx: ToolContext) -> Bool
    /// Delete: drop the last point drawn. False if there is none.
    func back() -> Bool
    /// Escape: drop what is being drawn. False if there was nothing.
    func cancel() -> Bool
    var preview: ToolPreview { get }
}

extension RoadToolHandler {
    func down(_ p: Pointer, _ ctx: ToolContext) {}
    func drag(_ p: Pointer, _ ctx: ToolContext) {}
    func up(_ p: Pointer, _ ctx: ToolContext) {}
    func hover(_ at: Vec2) {}
    func commit(_ ctx: ToolContext) -> Bool { false }
    func back() -> Bool { false }
    func cancel() -> Bool { false }
    var preview: ToolPreview { .none }
}

extension Tool {
    /// The handler of the tool.
    @MainActor
    func makeHandler() -> RoadToolHandler {
        switch self {
        case .select: SelectTool()
        case .addArea: DrawTool(closed: true) { RoadwayArea(id: "", op: "add", rings: [counterClockwise($0)]) }
        case .cutArea: DrawTool(closed: true) { RoadwayArea(id: "", op: "cut", rings: [counterClockwise($0)]) }
        case .line: DrawTool(closed: false) { LineMarking(id: "", points: $0) }
        case .zebra: DragPlaceTool { a, b in ZebraMarking(id: "", centre: (a + b) / 2, heading: (b - a).angle - 90, span: (b - a).length) }
        case .zigzag: DragPlaceTool { ZigzagMarking(id: "", points: [$0, $1]) }
        case .letter: ClickPlaceTool { LetterMarking(id: "", centre: $0, heading: 90) }
        case .shelter: ClickPlaceTool { BusShelter(id: "", position: $0, heading: 0) }
        }
    }
}

/// A ring wound counter-clockwise, as an area's outer ring is.
func counterClockwise(_ ring: [Vec2]) -> [Vec2] { signedArea(ring) < 0 ? ring.reversed() : ring }

