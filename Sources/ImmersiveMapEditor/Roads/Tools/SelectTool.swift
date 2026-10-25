import Foundation

/// Selects (click, shift-click, a box; command-click a whole area), moves
/// what is selected (drag; shift along 15 degree steps), turns it (option-
/// drag, or the frame's handle above; shift by 5 degrees), scales it (the
/// frame's corners, about the corner across, with option about its centre),
/// adds a point (double-click an edge).
@MainActor
final class SelectTool: RoadToolHandler {
    private enum Gesture {
        case none
        case move(from: Vec2, start: RoadPlan, began: Bool)
        case rotate(pivot: Vec2, from: Double, start: RoadPlan, began: Bool)
        case scale(pivot: Vec2, from: Double, start: RoadPlan, began: Bool)
        case box(from: Vec2, to: Vec2)
    }

    private var gesture = Gesture.none

    func down(_ p: Pointer, _ ctx: ToolContext) {
        let editor = ctx.editor
        // The selection's frame first: its handles lie over what is under them.
        if let frame = TransformFrame(editor.doc, editor.selection, pixel: ctx.tolerance / 7),
           let handle = frame.handle(at: p.at, reach: ctx.tolerance * 1.3) {
            switch handle {
            case .turn:
                gesture = .rotate(pivot: frame.centre, from: (p.at - frame.centre).angle, start: editor.doc, began: false)
            case .corner(let i):
                let pivot = frame.pivot(of: i, aboutCentre: p.option)
                gesture = .scale(pivot: pivot, from: max((p.at - pivot).length, 1e-6), start: editor.doc, began: false)
            }
            return
        }
        if p.clicks == 2, let (owner, ring, index, q) = ctx.hits.edge(p.at) {
            editor.insertPoint(owner, ring, after: index, at: q)
            gesture = .none
            return
        }
        var hit = ctx.hits.vertex(p.at) ?? ctx.hits.object(p.at)
        // A whole area only with command: a click on the roadway must not
        // pick up the whole network.
        if hit == nil && p.command { hit = ctx.hits.area(p.at) }
        guard let hit else {
            if !p.shift { editor.selection = [] }
            gesture = .box(from: p.at, to: p.at)
            return
        }
        if p.shift {
            if editor.selection.contains(hit) { editor.selection.remove(hit) } else { editor.selection.insert(hit) }
        } else if !editor.selection.contains(hit) {
            editor.selection = [hit]
        }
        if p.option, let pivot = editor.doc.centre(of: editor.selection) {
            gesture = .rotate(pivot: pivot, from: (p.at - pivot).angle, start: editor.doc, began: false)
        } else {
            gesture = .move(from: p.at, start: editor.doc, began: false)
        }
    }

    func drag(_ p: Pointer, _ ctx: ToolContext) {
        let editor = ctx.editor
        switch gesture {
        case let .move(from, start, began):
            if !began { editor.beginGesture("Move") }
            var d = p.at - from
            if p.shift {
                // Along the nearest 15 degree direction.
                d = Vec2.fromAngle((d.angle / 15).rounded() * 15) * d.length
            }
            editor.apply(start.moved(editor.selection, by: d))
            gesture = .move(from: from, start: start, began: true)
        case let .rotate(pivot, from, start, began):
            if !began { editor.beginGesture("Rotate") }
            var a = (p.at - pivot).angle - from
            if p.shift { a = (a / 5).rounded() * 5 }
            editor.apply(start.rotated(editor.selection, by: a, around: pivot))
            gesture = .rotate(pivot: pivot, from: from, start: start, began: true)
        case let .scale(pivot, from, start, began):
            if !began { editor.beginGesture("Scale") }
            let k = max(0.05, (p.at - pivot).length / from)
            editor.apply(start.scaled(editor.selection, by: k, around: pivot))
            gesture = .scale(pivot: pivot, from: from, start: start, began: true)
        case let .box(from, _):
            gesture = .box(from: from, to: p.at)
        case .none:
            break
        }
    }

    func up(_ p: Pointer, _ ctx: ToolContext) {
        if case let .box(from, to) = gesture {
            let picked = ctx.hits.box(from, to)
            ctx.editor.selection = p.shift ? ctx.editor.selection.union(picked) : picked
        }
        gesture = .none
    }

    var preview: ToolPreview {
        if case let .box(a, b) = gesture { return .box(a, b) }
        return .none
    }
}
