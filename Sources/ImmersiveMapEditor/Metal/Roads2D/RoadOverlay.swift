import Foundation

/// What changes with every gesture, drawn over the document: point handles,
/// the selection's outlines, OSM's crossings and stops, the tool's preview.
/// Built for each frame, for the points in view only.
@MainActor
enum RoadOverlay {
    static func mesh(_ editor: RoadEditor, hits: RoadHitTest, transform: ViewTransform2D, size: CGSize,
                     preview: ToolPreview) -> Mesh {
        var m = Mesh()
        let (lo, hi) = transform.visible(in: size)
        func visible(_ p: Vec2) -> Bool { p.x >= lo.x - 2 && p.x <= hi.x + 2 && p.y >= lo.y - 2 && p.y <= hi.y + 2 }
        let selected = editor.selection

        for (owner, ring, pts) in hits.pickable() {
            if editor.doc.object(owner) is RoadMarking { m.pixelPolyline(pts, width: 1, Colours.draft) }
            for (i, p) in pts.enumerated() where visible(p) {
                let on = selected.contains(.vertex(owner, ring: ring, index: i))
                m.pixelSquare(p, size: on ? 9 : 7, Colours.handleEdge)
                m.pixelSquare(p, size: on ? 7 : 5, on ? Colours.selected : Colours.handle)
            }
        }
        // Each object selected outlined as drawn, the way it faces ticked.
        for case .object(let id) in selected {
            guard let o = editor.doc.object(id) else { continue }
            for r in o.outline { m.pixelPolyline(r, closed: o.outlineClosed, width: 2, Colours.selected) }
            if let facing = o.facing {
                m.pixelLine(o.anchor, o.anchor + Vec2.fromAngle(facing) * (24 / transform.scale), width: 2, Colours.selected)
            }
        }
        // The selection's frame: corners that scale, a handle above that turns.
        if editor.tool == .select, let frame = TransformFrame(editor.doc, selected, pixel: 1 / transform.scale) {
            m.pixelPolyline(frame.corners, closed: true, width: 1, Colours.selected)
            m.pixelLine(frame.top, frame.turnHandle, width: 1, Colours.selected)
            for c in frame.corners + [frame.turnHandle] {
                m.pixelSquare(c, size: 10, Colours.handleEdge)
                m.pixelSquare(c, size: 8, Colours.handle)
            }
        }
        if editor.layers.centreLines {
            for p in editor.context.crossings where visible(p) { m.pixelSquare(p, size: 5, Colours.crossing) }
            for p in editor.context.stops where visible(p) { m.pixelSquare(p, size: 7, Colours.stop) }
        }
        switch preview {
        case let .draft(points, closed, pointer):
            m.pixelPolyline(points + (pointer.map { [$0] } ?? []), closed: closed, width: 2, Colours.draft)
            for p in points { m.pixelSquare(p, size: 7, Colours.draft) }
        case let .box(a, b):
            m.pixelPolyline([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, width: 1, Colours.draft)
        case let .line(a, b):
            m.pixelLine(a, b, width: 2, Colours.draft)
        case .none:
            break
        }
        return m
    }
}
