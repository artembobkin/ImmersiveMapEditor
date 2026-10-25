import Foundation

/// Places an object by a drag: a zebra across the road from kerb to kerb
/// (its bars run square to the drag), a zigzag along the kerb (the roadway
/// on the left of the drag). `make` makes it from the drag's ends.
@MainActor
final class DragPlaceTool: RoadToolHandler {
    let make: (Vec2, Vec2) -> RoadObject
    private var drag: (Vec2, Vec2)?

    init(_ make: @escaping (Vec2, Vec2) -> RoadObject) { self.make = make }

    func down(_ p: Pointer, _ ctx: ToolContext) { drag = (p.at, p.at) }

    func drag(_ p: Pointer, _ ctx: ToolContext) {
        if let (from, _) = drag { drag = (from, p.at) }
    }

    func up(_ p: Pointer, _ ctx: ToolContext) {
        defer { drag = nil }
        guard let (from, to) = drag, (to - from).length > 1 else { return }
        ctx.editor.add(make(from, to))
    }

    var preview: ToolPreview { drag.map { .line($0.0, $0.1) } ?? .none }
}

/// Places an object by a click: the letter A (its top north, turned with [
/// and ]) or a bus shelter (its length east, the road on its left). `make`
/// makes it at the click.
@MainActor
final class ClickPlaceTool: RoadToolHandler {
    let make: (Vec2) -> RoadObject

    init(_ make: @escaping (Vec2) -> RoadObject) { self.make = make }

    func down(_ p: Pointer, _ ctx: ToolContext) { ctx.editor.add(make(p.at)) }
}
