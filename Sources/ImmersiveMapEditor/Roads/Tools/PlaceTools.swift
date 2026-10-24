import Foundation

/// Places a marking by a drag: a zebra across the road from kerb to kerb
/// (its bars run square to the drag), a zigzag along the kerb (the roadway
/// on the left of the drag).
@MainActor
final class DragPlaceTool: RoadToolHandler {
    enum Kind { case zebra, zigzag }

    let kind: Kind
    private var drag: (Vec2, Vec2)?

    init(kind: Kind) { self.kind = kind }

    func down(_ p: Pointer, _ ctx: ToolContext) { drag = (p.at, p.at) }

    func drag(_ p: Pointer, _ ctx: ToolContext) {
        if let (from, _) = drag { drag = (from, p.at) }
    }

    func up(_ p: Pointer, _ ctx: ToolContext) {
        defer { drag = nil }
        guard let (from, to) = drag, (to - from).length > 1 else { return }
        let d = to - from
        switch kind {
        case .zebra:
            ctx.editor.addMarking(RoadPlan.Marking(id: "", kind: "zebra", centre: (from + to) / 2,
                                                       heading: d.angle - 90, span: d.length))
        case .zigzag:
            ctx.editor.addMarking(RoadPlan.Marking(id: "", kind: "zigzag", points: [from, to]))
        }
    }

    var preview: ToolPreview { drag.map { .line($0.0, $0.1) } ?? .none }
}

/// Places a thing by a click: the letter A (its top north, turned with [
/// and ]) or a bus shelter (its length east, the road on its left).
@MainActor
final class ClickPlaceTool: RoadToolHandler {
    enum Kind { case letter, shelter }

    let kind: Kind

    init(kind: Kind) { self.kind = kind }

    func down(_ p: Pointer, _ ctx: ToolContext) {
        switch kind {
        case .letter: ctx.editor.addMarking(RoadPlan.Marking(id: "", kind: "letter", centre: p.at, heading: 90))
        case .shelter: ctx.editor.addShelter(at: p.at, heading: 0)
        }
    }
}
