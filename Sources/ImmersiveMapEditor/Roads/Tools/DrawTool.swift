import Foundation

/// Draws an area of roadway to add or cut (click the corners, Return or a
/// click on the first point closes it) or a line marking (click the points,
/// Return or a double-click finishes). Delete drops the last point.
@MainActor
final class DrawTool: RoadToolHandler {
    enum Kind {
        case area(op: String)
        case line
    }

    let kind: Kind
    private var points: [Vec2] = []
    private var pointer: Vec2?

    init(kind: Kind) { self.kind = kind }

    private var closed: Bool {
        if case .area = kind { return true }
        return false
    }

    func down(_ p: Pointer, _ ctx: ToolContext) {
        if closed, points.count >= 3, (points[0] - p.at).length < ctx.tolerance {
            _ = commit(ctx)
        } else if !closed && p.clicks == 2 {
            _ = commit(ctx)
        } else {
            points.append(p.at)
        }
    }

    func hover(_ at: Vec2) { pointer = at }

    func commit(_ ctx: ToolContext) -> Bool {
        guard !points.isEmpty else { return false }
        switch kind {
        case .area(let op):
            ctx.editor.addArea(points, op: op)
        case .line where points.count >= 2:
            ctx.editor.addMarking(RoadPlan.Marking(id: "", kind: "line", style: "dashed", points: points))
        case .line:
            break
        }
        points = []
        return true
    }

    func back() -> Bool {
        guard !points.isEmpty else { return false }
        points.removeLast()
        return true
    }

    func cancel() -> Bool {
        guard !points.isEmpty else { return false }
        points = []
        return true
    }

    var preview: ToolPreview { points.isEmpty ? .none : .draft(points, closed: closed, pointer: pointer) }
}
