import Foundation

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
        case .addArea: DrawTool(kind: .area(op: "add"))
        case .cutArea: DrawTool(kind: .area(op: "cut"))
        case .line: DrawTool(kind: .line)
        case .zebra: DragPlaceTool(kind: .zebra)
        case .zigzag: DragPlaceTool(kind: .zigzag)
        case .letter: ClickPlaceTool(kind: .letter)
        case .shelter: ClickPlaceTool(kind: .shelter)
        }
    }
}
