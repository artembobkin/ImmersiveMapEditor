/// The points of an intersection's result: the nodes where edges of both
/// inputs meet and no result edge does: JTS's `IntersectionPointBuilder`.
final class IntersectionPointBuilder {
    private let factory: GeometryFactory
    private let graph: OverlayGraph
    @exclusivity(unchecked) private var points: [Point] = []
    @exclusivity(unchecked) private var isAllowCollapseLines = !OverlayNG.strictModeDefault

    init(_ graph: OverlayGraph, _ factory: GeometryFactory) {
        self.graph = graph
        self.factory = factory
    }

    func setStrictMode(_ isStrictMode: Bool) { isAllowCollapseLines = !isStrictMode }

    func getPoints() -> [Point] {
        for nodeEdge in graph.nodeEdges where isResultPoint(nodeEdge) {
            points.append(factory.createPoint(nodeEdge.coordinate))
        }
        return points
    }

    private func isResultPoint(_ nodeEdge: OverlayEdge) -> Bool {
        var isEdgeOfA = false, isEdgeOfB = false
        var edge = nodeEdge
        repeat {
            if edge.isInResult { return false }
            isEdgeOfA = isEdgeOfA || isEdgeOf(edge.label, 0)
            isEdgeOfB = isEdgeOfB || isEdgeOf(edge.label, 1)
            edge = edge.oNextOE
        } while edge !== nodeEdge
        return isEdgeOfA && isEdgeOfB
    }

    private func isEdgeOf(_ label: OverlayLabel, _ i: Int) -> Bool {
        if !isAllowCollapseLines && label.isBoundaryCollapse() { return false }
        return label.isBoundary(i) || label.isLine(i)
    }
}
