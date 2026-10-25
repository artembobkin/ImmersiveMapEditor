/// Labels the overlay graph: the area locations carried around every node,
/// the line locations carried along connected linear edges, collapsed edges
/// by whether they came from a hole, and the edges left by locating them
/// in the input areas; then marks the result area edges: JTS's
/// `OverlayLabeller`.
final class OverlayLabeller {
    private let graph: OverlayGraph
    private let inputGeometry: InputGeometry
    private let edges: [OverlayEdge]

    init(_ graph: OverlayGraph, _ inputGeometry: InputGeometry) {
        self.graph = graph
        self.inputGeometry = inputGeometry
        edges = graph.edges
    }

    func computeLabelling() throws {
        try labelAreaNodeEdges(graph.nodeEdges)
        labelConnectedLinearEdges()
        // Collapsed edges labelled after the connected linear ones, so the
        // locations they carry go on along them.
        labelCollapsedEdges()
        labelConnectedLinearEdges()
        labelDisconnectedEdges()
    }

    private func labelAreaNodeEdges(_ nodes: [OverlayEdge]) throws {
        for nodeEdge in nodes {
            try propagateAreaLocations(nodeEdge, 0)
            if inputGeometry.hasEdges(1) { try propagateAreaLocations(nodeEdge, 1) }
        }
    }

    /// Carries the side locations of an input's area boundaries around a
    /// node to the edges between them, checking they agree.
    func propagateAreaLocations(_ nodeEdge: OverlayEdge, _ geomIndex: Int) throws {
        if !inputGeometry.isArea(geomIndex) { return }
        if nodeEdge.degree() == 1 { return }
        guard let eStart = try OverlayLabeller.findPropagationStartEdge(nodeEdge, geomIndex) else { return }
        var currLoc = eStart.getLocation(geomIndex, Position.left)
        var e = eStart.oNextOE
        repeat {
            let label = e.label
            if !label.isBoundary(geomIndex) {
                label.setLocationLine(geomIndex, currLoc)
            } else {
                try Assert.isTrue(label.hasSides(geomIndex))
                let locRight = e.getLocation(geomIndex, Position.right)
                if locRight != currLoc {
                    throw TopologyException("side location conflict: arg \(geomIndex)", e.coordinate)
                }
                let locLeft = e.getLocation(geomIndex, Position.left)
                if locLeft == Location.none { throw Assert.shouldNeverReachHere("found single null side at \(e.coordinate)") }
                currLoc = locLeft
            }
            e = e.oNextOE
        } while e !== eStart
    }

    private static func findPropagationStartEdge(_ nodeEdge: OverlayEdge, _ geomIndex: Int) throws -> OverlayEdge? {
        var eStart = nodeEdge
        repeat {
            let label = eStart.label
            if label.isBoundary(geomIndex) {
                try Assert.isTrue(label.hasSides(geomIndex))
                return eStart
            }
            eStart = eStart.oNextOE
        } while eStart !== nodeEdge
        return nil
    }

    private func labelCollapsedEdges() {
        for edge in edges {
            if edge.label.isLineLocationUnknown(0) { labelCollapsedEdge(edge, 0) }
            if edge.label.isLineLocationUnknown(1) { labelCollapsedEdge(edge, 1) }
        }
    }

    private func labelCollapsedEdge(_ edge: OverlayEdge, _ geomIndex: Int) {
        let label = edge.label
        if !label.isCollapse(geomIndex) { return }
        label.setLocationCollapse(geomIndex)
    }

    private func labelConnectedLinearEdges() {
        propagateLinearLocations(0)
        if inputGeometry.hasEdges(1) { propagateLinearLocations(1) }
    }

    /// Carries line locations from the linear edges that have one to the
    /// edges connected to them, depth first (JTS's deque used as a stack).
    private func propagateLinearLocations(_ geomIndex: Int) {
        let linearEdges = OverlayLabeller.findLinearEdgesWithLocation(edges, geomIndex)
        if linearEdges.isEmpty { return }
        // A deque taken from its front and pushed onto its front: an array
        // whose last element is the front.
        var edgeStack = Array(linearEdges.reversed())
        let isInputLine = inputGeometry.isLine(geomIndex)
        while let lineEdge = edgeStack.popLast() {
            OverlayLabeller.propagateLinearLocationAtNode(lineEdge, geomIndex, isInputLine, &edgeStack)
        }
    }

    private static func propagateLinearLocationAtNode(_ eNode: OverlayEdge, _ geomIndex: Int, _ isInputLine: Bool,
                                                      _ edgeStack: inout [OverlayEdge]) {
        let lineLoc = eNode.label.getLineLocation(geomIndex)
        // Only the exterior location of an input line is carried on.
        if isInputLine && lineLoc != Location.exterior { return }
        var e = eNode.oNextOE
        repeat {
            let label = e.label
            if label.isLineLocationUnknown(geomIndex) {
                label.setLocationLine(geomIndex, lineLoc)
                edgeStack.append(e.symOE)
            }
            e = e.oNextOE
        } while e !== eNode
    }

    private static func findLinearEdgesWithLocation(_ edges: [OverlayEdge], _ geomIndex: Int) -> [OverlayEdge] {
        edges.filter { $0.label.isLinear(geomIndex) && !$0.label.isLineLocationUnknown(geomIndex) }
    }

    private func labelDisconnectedEdges() {
        for edge in edges {
            if edge.label.isLineLocationUnknown(0) { labelDisconnectedEdge(edge, 0) }
            if edge.label.isLineLocationUnknown(1) { labelDisconnectedEdge(edge, 1) }
        }
    }

    /// An edge not connected to the input's edges is inside its area when
    /// both its ends are.
    private func labelDisconnectedEdge(_ edge: OverlayEdge, _ geomIndex: Int) {
        let label = edge.label
        if !inputGeometry.isArea(geomIndex) {
            label.setLocationAll(geomIndex, Location.exterior)
            return
        }
        label.setLocationAll(geomIndex, locateEdgeBothEnds(geomIndex, edge))
    }

    private func locateEdgeBothEnds(_ geomIndex: Int, _ edge: OverlayEdge) -> Int {
        let locOrig = inputGeometry.locatePointInArea(geomIndex, edge.orig)
        let locDest = inputGeometry.locatePointInArea(geomIndex, edge.dest)
        let isInt = locOrig != Location.exterior && locDest != Location.exterior
        return isInt ? Location.interior : Location.exterior
    }

    func markResultAreaEdges(_ overlayOpCode: Int) {
        for edge in edges { markInResultArea(edge, overlayOpCode) }
    }

    /// An edge bounds the result area when the result is on its right.
    func markInResultArea(_ e: OverlayEdge, _ overlayOpCode: Int) {
        let label = e.label
        if label.isBoundaryEither()
            && OverlayNG.isResultOfOp(overlayOpCode,
                                      label.getLocationBoundaryOrLine(0, Position.right, e.isForward),
                                      label.getLocationBoundaryOrLine(1, Position.right, e.isForward)) {
            e.markInResultArea()
        }
    }

    /// An edge with the result on both sides is inside it, not its boundary.
    func unmarkDuplicateEdgesFromResultArea() {
        for edge in edges where edge.isInResultAreaBoth { edge.unmarkFromResultAreaBoth() }
    }
}
