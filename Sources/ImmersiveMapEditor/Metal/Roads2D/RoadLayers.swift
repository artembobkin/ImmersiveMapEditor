import Foundation
import Geometry

/// The road document as meshes, in the order they are drawn: the buildings
/// under it, the kerb, the roadway (added areas, then cut ones), the paint,
/// the shelters, the OSM centre lines and the tiles' edges. Built again
/// whenever the document changes (its revision).
@MainActor
struct RoadLayers {
    var revision = -1
    var buildings = StencilBatch()
    var buildingEdges = Mesh()
    var kerb = Mesh()
    var roadway = StencilBatch()
    var cuts = StencilBatch()
    var cutEdges = Mesh()
    var paint = Mesh()
    var letters = StencilBatch()
    var shelters = Mesh()
    var centreLines = Mesh()
    var grid = Mesh()

    init() {}

    init(_ model: RoadEditor) {
        revision = model.revision
        let doc = model.doc
        buildings = StencilBatch()
        buildingEdges = Mesh()
        for b in model.context.buildings where b.count >= 3 {
            buildings.add([signedArea(b) < 0 ? b.reversed() : b])
            buildingEdges.pixelPolyline(b, closed: true, width: 1, Colours.buildingEdge)
        }
        buildings.close(Colours.building)

        kerb = Mesh()
        roadway = StencilBatch()
        cuts = StencilBatch()
        cutEdges = Mesh()
        for a in doc.areas {
            if a.op == "add" {
                roadway.add(a.rings)
                for ring in a.rings {
                    for i in ring.indices { kerb.band(ring[i], ring[(i + 1) % ring.count], width: 0.7, Colours.kerb) }
                }
            } else {
                cuts.add(a.rings)
                for ring in a.rings { cutEdges.pixelPolyline(ring, closed: true, width: 1.5, Colours.cutEdge) }
            }
        }
        roadway.close(Colours.asphalt)
        cuts.close(Colours.ground)

        paint = Mesh()
        letters = StencilBatch()
        for m in doc.markings {
            switch m.kind {
            case "line":
                for q in MarkingShapes.lineQuads(m) { paint.convex(q, m.colour == "yellow" ? Colours.yellow : Colours.marking) }
            case "zebra":
                for (q, whole) in MarkingShapes.zebraBars(m, inside: model.onRoadway) {
                    paint.convex(q, whole ? Colours.marking : Colours.bad)
                }
            case "zigzag":
                for q in MarkingShapes.stroke(MarkingShapes.zigzag(m), width: MarkingShapes.zigzagLine) {
                    paint.convex(q, Colours.yellow)
                }
            default:
                letters.add(MarkingShapes.letterRings(m))
            }
        }
        letters.close(Colours.marking)

        shelters = Mesh()
        for s in doc.shelters {
            let r = MarkingShapes.shelterRect(s)
            shelters.convex(r, Colours.shelter)
            shelters.pixelPolyline(r, closed: true, width: 1.5, Colours.shelterEdge)
            // The open side, to the road.
            shelters.pixelLine(r[3], r[2], width: 3, Colours.draft)
        }

        centreLines = Mesh()
        for r in model.context.roads {
            let pedestrian = ["footway", "pedestrian"].contains(r.highway)
            centreLines.pixelPolyline(r.points, width: pedestrian ? 1 : 1.5,
                                      pedestrian ? rgb(0x3C7DD9, 0.25) : Colours.centreLine)
        }

        grid = Mesh()
        let t = doc.tiles
        let proj = doc.projection
        for y in t.y0...t.y1 {
            for x in t.x0...t.x1 {
                let (a, b) = proj.tileRect(x: x, y: y)
                grid.pixelPolyline([a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, width: 1.5, Colours.tileEdge)
            }
        }
    }
}
