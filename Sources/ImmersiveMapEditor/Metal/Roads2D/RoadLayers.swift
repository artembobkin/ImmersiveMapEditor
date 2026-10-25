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
        paint = Mesh()
        letters = StencilBatch()
        shelters = Mesh()
        // What every object paints, into the meshes of its layer: the
        // objects say what they are made of, this how it is drawn.
        for o in doc.objects {
            for p in o.paint(onRoadway: model.onRoadway) { add(p) }
        }
        roadway.close(Colours.asphalt)
        cuts.close(Colours.ground)
        letters.close(Colours.marking)

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

    /// One paint into its layer's mesh.
    private mutating func add(_ p: Paint) {
        let colour = Self.colour(p.ink)
        switch (p.layer, p.form) {
        case (.roadway, .rings(let r)): roadway.add(r)
        case (.cuts, .rings(let r)): cuts.add(r)
        case (.markings, .rings(let r)): letters.add(r)
        case (_, .rings(let r)): for ring in r { shelters.convex(ring, colour) }
        case (.roadway, .band(let a, let b, let w)): kerb.band(a, b, width: w, colour)
        case (_, .band(let a, let b, let w)): paint.band(a, b, width: w, colour)
        case (.markings, .convex(let q)): paint.convex(q, colour)
        case (_, .convex(let q)): shelters.convex(q, colour)
        case (.cuts, .outline(let pts, let closed, let w)): cutEdges.pixelPolyline(pts, closed: closed, width: w, colour)
        case (_, .outline(let pts, let closed, let w)): shelters.pixelPolyline(pts, closed: closed, width: w, colour)
        }
    }

    private static func colour(_ ink: Paint.Ink) -> SIMD4<Float> {
        switch ink {
        case .asphalt: Colours.asphalt
        case .kerb: Colours.kerb
        case .ground: Colours.ground
        case .cutEdge: Colours.cutEdge
        case .white: Colours.marking
        case .yellow: Colours.yellow
        case .wrong: Colours.bad
        case .shelter: Colours.shelter
        case .shelterEdge: Colours.shelterEdge
        case .open: Colours.draft
        }
    }
}
