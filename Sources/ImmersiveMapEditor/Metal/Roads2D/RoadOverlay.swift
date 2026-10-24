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
            if case .marking = owner { m.pixelPolyline(pts, width: 1, Colours.draft) }
            for (i, p) in pts.enumerated() where visible(p) {
                let on = selected.contains(.vertex(owner, ring: ring, index: i))
                m.pixelSquare(p, size: on ? 9 : 7, Colours.handleEdge)
                m.pixelSquare(p, size: on ? 7 : 5, on ? Colours.selected : Colours.handle)
            }
        }
        for item in selected {
            switch item {
            case .marking(let i):
                let k = editor.doc.markings[i]
                switch k.kind {
                case "zebra": m.pixelPolyline(MarkingShapes.zebraZone(k), closed: true, width: 2, Colours.selected)
                case "letter":
                    for r in MarkingShapes.letterRings(k) { m.pixelPolyline(r, closed: true, width: 2, Colours.selected) }
                case "zigzag": m.pixelPolyline(MarkingShapes.zigzag(k), width: 2, Colours.selected)
                default: m.pixelPolyline(k.points, width: 2, Colours.selected)
                }
                // Its heading.
                if k.kind == "zebra" || k.kind == "letter" {
                    m.pixelLine(k.centre, k.centre + Vec2.fromAngle(k.heading) * (24 / transform.scale), width: 2, Colours.selected)
                }
            case .shelter(let i):
                m.pixelPolyline(MarkingShapes.shelterRect(editor.doc.shelters[i]), closed: true, width: 2.5, Colours.selected)
            case .area(let i):
                for r in editor.doc.areas[i].rings { m.pixelPolyline(r, closed: true, width: 2, Colours.selected) }
            case .vertex:
                break
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
