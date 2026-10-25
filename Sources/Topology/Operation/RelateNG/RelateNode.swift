/// A node of RelateNG: the edges of both geometries leaving it, sorted by
/// angle, and their side locations filled in around it: JTS's `RelateNode`.
final class RelateNode {
    let nodePt: Coordinate
    @exclusivity(unchecked) private(set) var edges: [RelateEdge] = []

    init(_ pt: Coordinate) { nodePt = pt }

    func addEdges(_ nss: [NodeSection]) {
        for ns in nss { addEdges(ns) }
    }

    func addEdges(_ ns: NodeSection) {
        switch ns.dim {
        case Dimension.l:
            _ = addEdge(ns.isA, ns.getVertex(0), Dimension.l, false)
            _ = addEdge(ns.isA, ns.getVertex(1), Dimension.l, false)
        case Dimension.a:
            // The area of a section is to the right of its direction.
            let e0 = addEdge(ns.isA, ns.getVertex(0), Dimension.a, false)
            let e1 = addEdge(ns.isA, ns.getVertex(1), Dimension.a, true)
            let index0 = e0.flatMap { e in edges.firstIndex { $0 === e } } ?? -1
            let index1 = e1.flatMap { e in edges.firstIndex { $0 === e } } ?? -1
            updateEdgesInArea(ns.isA, index0, index1)
            updateIfAreaPrev(ns.isA, index0)
            updateIfAreaNext(ns.isA, index1)
        default: break
        }
    }

    private func updateEdgesInArea(_ isA: Bool, _ indexFrom: Int, _ indexTo: Int) {
        var index = RelateNode.nextIndex(edges, indexFrom)
        while index != indexTo {
            edges[index].setAreaInterior(isA)
            index = RelateNode.nextIndex(edges, index)
        }
    }

    private func updateIfAreaPrev(_ isA: Bool, _ index: Int) {
        let indexPrev = RelateNode.prevIndex(edges, index)
        if edges[indexPrev].isInterior(isA, Position.left) { edges[index].setAreaInterior(isA) }
    }

    private func updateIfAreaNext(_ isA: Bool, _ index: Int) {
        let indexNext = RelateNode.nextIndex(edges, index)
        if edges[indexNext].isInterior(isA, Position.right) { edges[index].setAreaInterior(isA) }
    }

    /// The edge of this direction, merged into one already there.
    private func addEdge(_ isA: Bool, _ dirPt: Coordinate?, _ dim: Int, _ isForward: Bool) -> RelateEdge? {
        guard let dirPt else { return nil }
        if nodePt.equals2D(dirPt) { return nil }
        var insertIndex = -1
        for (i, e) in edges.enumerated() {
            let comp = e.compareToEdge(dirPt)
            if comp == 0 {
                e.merge(isA, dirPt, dim, isForward)
                return e
            }
            if comp == 1 {
                insertIndex = i
                break
            }
        }
        let e = RelateEdge.create(self, dirPt, isA, dim, isForward)
        if insertIndex < 0 { edges.append(e) } else { edges.insert(e, at: insertIndex) }
        return e
    }

    func finish(_ isAreaInteriorA: Bool, _ isAreaInteriorB: Bool) {
        finishNode(true, isAreaInteriorA)
        finishNode(false, isAreaInteriorB)
    }

    private func finishNode(_ isA: Bool, _ isAreaInterior: Bool) {
        if isAreaInterior {
            RelateEdge.setAreaInterior(edges, isA)
        } else {
            let startIndex = RelateEdge.findKnownEdgeIndex(edges, isA)
            propagateSideLocations(isA, startIndex)
        }
    }

    private func propagateSideLocations(_ isA: Bool, _ startIndex: Int) {
        var currLoc = edges[startIndex].location(isA, Position.left)
        var index = RelateNode.nextIndex(edges, startIndex)
        while index != startIndex {
            let e = edges[index]
            e.setUnknownLocations(isA, currLoc)
            currLoc = e.location(isA, Position.left)
            index = RelateNode.nextIndex(edges, index)
        }
    }

    private static func prevIndex(_ list: [RelateEdge], _ index: Int) -> Int { index > 0 ? index - 1 : list.count - 1 }
    private static func nextIndex(_ list: [RelateEdge], _ i: Int) -> Int { i >= list.count - 1 ? 0 : i + 1 }

    func hasExteriorEdge(_ isA: Bool) -> Bool {
        edges.contains { Location.exterior == $0.location(isA, Position.left) || Location.exterior == $0.location(isA, Position.right) }
    }
}
