import Foundation

/// Draws an object point by point: an area of roadway to add or cut
/// (`closed`: click the corners, Return or a click on the first point closes
/// it) or a line marking (click the points, Return or a double-click
/// finishes). Delete drops the last point. `make` makes it from the points.
@MainActor
final class DrawTool: RoadToolHandler {
    let closed: Bool
    let make: ([Vec2]) -> RoadObject
    private var points: [Vec2] = []
    private var pointer: Vec2?

    init(closed: Bool, _ make: @escaping ([Vec2]) -> RoadObject) {
        self.closed = closed
        self.make = make
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
        if points.count >= (closed ? 3 : 2) { ctx.editor.add(make(points)) }
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
