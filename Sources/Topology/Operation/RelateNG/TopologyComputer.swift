/// Builds the topology of two geometries for a predicate: the dimensions
/// of the intersections their elements make, point by point and node by
/// node, stopping as soon as the predicate is known: JTS's `TopologyComputer`.
/// GEOS keeps the nodes in an ordered map, and evaluates them in the order
/// of their coordinates, as here.
final class TopologyComputer {
    private let predicate: TopologyPredicate
    private let geomA: RelateGeometry
    private let geomB: RelateGeometry
    @exclusivity(unchecked) private var nodeMap: [Coordinate: NodeSections] = [:]

    init(_ predicate: TopologyPredicate, _ geomA: RelateGeometry, _ geomB: RelateGeometry) {
        self.predicate = predicate
        self.geomA = geomA
        self.geomB = geomB
        initExteriorDims()
    }

    /// The exterior intersections known from the dimensions alone.
    private func initExteriorDims() {
        let dimRealA = geomA.dimensionReal, dimRealB = geomB.dimensionReal
        let (p, l, a) = (Dimension.p, Dimension.l, Dimension.a)
        let (i, b, e) = (Location.interior, Location.boundary, Location.exterior)
        if dimRealA == p && dimRealB == l {
            updateDim(e, i, l)
        } else if dimRealA == l && dimRealB == p {
            updateDim(i, e, l)
        } else if dimRealA == p && dimRealB == a {
            updateDim(e, i, a)
            updateDim(e, b, l)
        } else if dimRealA == a && dimRealB == p {
            updateDim(i, e, a)
            updateDim(b, e, l)
        } else if dimRealA == l && dimRealB == a {
            updateDim(e, i, a)
        } else if dimRealA == a && dimRealB == l {
            updateDim(i, e, a)
        } else if dimRealA == Dimension.false || dimRealB == Dimension.false {
            if dimRealA != Dimension.false { initExteriorEmpty(RelateGeometry.geomA) }
            if dimRealB != Dimension.false { initExteriorEmpty(RelateGeometry.geomB) }
        }
    }

    private func initExteriorEmpty(_ geomNonEmpty: Bool) {
        switch getDimension(geomNonEmpty) {
        case Dimension.p:
            updateDim(geomNonEmpty, Location.interior, Location.exterior, Dimension.p)
        case Dimension.l:
            if getGeometry(geomNonEmpty).hasBoundary {
                updateDim(geomNonEmpty, Location.boundary, Location.exterior, Dimension.p)
            }
            updateDim(geomNonEmpty, Location.interior, Location.exterior, Dimension.l)
        case Dimension.a:
            updateDim(geomNonEmpty, Location.boundary, Location.exterior, Dimension.l)
            updateDim(geomNonEmpty, Location.interior, Location.exterior, Dimension.a)
        default: break
        }
    }

    private func getGeometry(_ isA: Bool) -> RelateGeometry { isA ? geomA : geomB }
    func getDimension(_ isA: Bool) -> Int { getGeometry(isA).dimension }
    var isAreaArea: Bool { getDimension(true) == Dimension.a && getDimension(false) == Dimension.a }

    var isSelfNodingRequired: Bool {
        predicate.requireSelfNoding() && (geomA.isSelfNodingRequired || geomB.isSelfNodingRequired)
    }

    func isExteriorCheckRequired(_ isA: Bool) -> Bool { predicate.requireExteriorCheck(isA) }

    private func updateDim(_ locA: Int, _ locB: Int, _ dimension: Int) {
        predicate.updateDimension(locA, locB, dimension)
    }

    /// The locations in the order of the geometry they are of.
    private func updateDim(_ isAB: Bool, _ loc1: Int, _ loc2: Int, _ dimension: Int) {
        if isAB { updateDim(loc1, loc2, dimension) } else { updateDim(loc2, loc1, dimension) }
    }

    func isResultKnown() -> Bool { predicate.isKnown() }
    func getResult() -> Bool { predicate.value() }
    func finish() { predicate.finish() }

    private func getNodeSections(_ nodePt: Coordinate) -> NodeSections {
        if let node = nodeMap[nodePt] { return node }
        let node = NodeSections(nodePt)
        nodeMap[nodePt] = node
        return node
    }

    func addIntersection(_ a: NodeSection, _ b: NodeSection) {
        if !a.isSameGeometry(b) { updateIntersectionAB(a, b) }
        // Sections of one geometry are kept too, for its self-intersections.
        let sections = getNodeSections(a.nodePt)
        sections.addNodeSection(a)
        sections.addNodeSection(b)
    }

    private func updateIntersectionAB(_ a: NodeSection, _ b: NodeSection) {
        if NodeSection.isAreaArea(a, b) { updateAreaAreaCross(a, b) }
        updateNodeLocation(a, b)
    }

    private func updateAreaAreaCross(_ a: NodeSection, _ b: NodeSection) {
        if NodeSection.isProper(a, b)
            || PolygonNodeTopology.isCrossing(a.nodePt, a.getVertex(0)!, a.getVertex(1)!, b.getVertex(0)!, b.getVertex(1)!) {
            updateDim(Location.interior, Location.interior, Dimension.a)
        }
    }

    private func updateNodeLocation(_ a: NodeSection, _ b: NodeSection) {
        let pt = a.nodePt
        let locA = geomA.locateNode(pt, a.poly)
        let locB = geomB.locateNode(pt, b.poly)
        updateDim(locA, locB, Dimension.p)
    }

    func addPointOnPointInterior(_ pt: Coordinate?) { updateDim(Location.interior, Location.interior, Dimension.p) }
    func addPointOnPointExterior(_ isGeomA: Bool, _ pt: Coordinate?) {
        updateDim(isGeomA, Location.interior, Location.exterior, Dimension.p)
    }

    func addPointOnGeometry(_ isA: Bool, _ locTarget: Int, _ dimTarget: Int, _ pt: Coordinate) throws {
        updateDim(isA, Location.interior, locTarget, Dimension.p)
        switch dimTarget {
        case Dimension.p, Dimension.l: return
        case Dimension.a:
            // A point in an area: the area's interior and boundary are outside the point.
            updateDim(isA, Location.exterior, Location.interior, Dimension.a)
            updateDim(isA, Location.exterior, Location.boundary, Dimension.l)
        default: throw IllegalStateException("Unknown target dimension: \(dimTarget)")
        }
    }

    func addLineEndOnGeometry(_ isLineA: Bool, _ locLineEnd: Int, _ locTarget: Int, _ dimTarget: Int, _ pt: Coordinate) throws {
        updateDim(isLineA, locLineEnd, locTarget, Dimension.p)
        switch dimTarget {
        case Dimension.p: return
        case Dimension.l:
            if locTarget == Location.exterior { updateDim(isLineA, Location.interior, Location.exterior, Dimension.l) }
        case Dimension.a:
            if locTarget != Location.boundary {
                updateDim(isLineA, Location.interior, locTarget, Dimension.l)
                updateDim(isLineA, Location.exterior, locTarget, Dimension.a)
            }
        default: throw IllegalStateException("Unknown target dimension: \(dimTarget)")
        }
    }

    func addAreaVertex(_ isAreaA: Bool, _ locArea: Int, _ locTarget: Int, _ dimTarget: Int, _ pt: Coordinate) throws {
        if locTarget == Location.exterior {
            updateDim(isAreaA, Location.interior, Location.exterior, Dimension.a)
            if locArea == Location.boundary {
                updateDim(isAreaA, Location.boundary, Location.exterior, Dimension.l)
                updateDim(isAreaA, Location.exterior, Location.exterior, Dimension.a)
            }
            return
        }
        switch dimTarget {
        case Dimension.p:
            updateDim(isAreaA, locArea, Location.interior, Dimension.p)
            updateDim(isAreaA, Location.interior, Location.exterior, Dimension.a)
            if locArea == Location.boundary {
                updateDim(isAreaA, Location.boundary, Location.exterior, Dimension.l)
                updateDim(isAreaA, Location.exterior, Location.exterior, Dimension.a)
            }
        case Dimension.l:
            updateDim(isAreaA, locArea, locTarget, Dimension.p)
            if locArea == Location.interior { updateDim(isAreaA, Location.interior, Location.exterior, Dimension.a) }
        case Dimension.a:
            addAreaVertexOnArea(isAreaA, locArea, locTarget, pt)
        default: throw IllegalStateException("Unknown target dimension: \(dimTarget)")
        }
    }

    func addAreaVertexOnArea(_ isAreaA: Bool, _ locArea: Int, _ locTarget: Int, _ pt: Coordinate) {
        if locTarget == Location.boundary {
            if locArea == Location.boundary {
                updateDim(isAreaA, Location.boundary, Location.boundary, Dimension.p)
            } else {
                updateDim(isAreaA, Location.interior, Location.interior, Dimension.a)
                updateDim(isAreaA, Location.interior, Location.boundary, Dimension.l)
                updateDim(isAreaA, Location.interior, Location.exterior, Dimension.a)
            }
        } else {
            updateDim(isAreaA, Location.interior, locTarget, Dimension.a)
            if locArea == Location.boundary {
                updateDim(isAreaA, Location.boundary, locTarget, Dimension.l)
                updateDim(isAreaA, Location.exterior, locTarget, Dimension.a)
            }
        }
    }

    /// The nodes where both geometries meet, in the order of their points.
    func evaluateNodes() {
        for key in nodeMap.keys.sorted() {
            let nodeSections = nodeMap[key]!
            if nodeSections.hasInteractionAB() {
                evaluateNode(nodeSections)
                if isResultKnown() { return }
            }
        }
    }

    private func evaluateNode(_ nodeSections: NodeSections) {
        let p = nodeSections.nodePt
        let node = nodeSections.createNode()
        let isAreaInteriorA = geomA.isNodeInArea(p, nodeSections.getPolygonal(RelateGeometry.geomA))
        let isAreaInteriorB = geomB.isNodeInArea(p, nodeSections.getPolygonal(RelateGeometry.geomB))
        node.finish(isAreaInteriorA, isAreaInteriorB)
        for e in node.edges {
            if isAreaArea {
                updateDim(e.location(true, Position.left), e.location(false, Position.left), Dimension.a)
                updateDim(e.location(true, Position.right), e.location(false, Position.right), Dimension.a)
            }
            updateDim(e.location(true, Position.on), e.location(false, Position.on), Dimension.l)
        }
    }
}
