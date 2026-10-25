/// Locates a point on the boundaries of several polygons that may be
/// adjacent (a multipolygon's parts sharing edges, which is valid): on
/// their common boundary it is interior: JTS's `AdjacentEdgeLocator`.
final class AdjacentEdgeLocator {
    @exclusivity(unchecked) private var ringList: [[Coordinate]] = []

    init(_ geom: Geometry) {
        if geom.isEmpty() { return }
        addRings(geom)
    }

    func locate(_ p: Coordinate) -> Int {
        let sections = NodeSections(p)
        for ring in ringList { addSections(p, ring, sections) }
        let node = sections.createNode()
        return node.hasExteriorEdge(true) ? Location.boundary : Location.interior
    }

    private func addSections(_ p: Coordinate, _ ring: [Coordinate], _ sections: NodeSections) {
        for i in stride(from: 0, to: ring.count - 1, by: 1) {
            let p0 = ring[i], pnext = ring[i + 1]
            if p.equals2D(pnext) {
                // The section is added by the next segment.
                continue
            } else if p.equals2D(p0) {
                let iprev = i > 0 ? i - 1 : ring.count - 2
                sections.addNodeSection(createSection(p, ring[iprev], pnext))
            } else if PointLocation.isOnSegment(p, p0, pnext) {
                sections.addNodeSection(createSection(p, p0, pnext))
            }
        }
    }

    private func createSection(_ p: Coordinate, _ prev: Coordinate, _ next: Coordinate) -> NodeSection {
        NodeSection(true, Dimension.a, 1, 0, nil, false, prev, p, next)
    }

    private func addRings(_ geom: Geometry) {
        if let poly = geom as? Polygon {
            addRing(poly.shell, true)
            for hole in poly.holes { addRing(hole, false) }
        } else if let gc = geom as? GeometryCollection {
            for g in gc.geometries { addRings(g) }
        }
    }

    private func addRing(_ ring: LinearRing, _ requireCW: Bool) {
        ringList.append(RelateGeometry.orient(ring.points, requireCW))
    }
}
