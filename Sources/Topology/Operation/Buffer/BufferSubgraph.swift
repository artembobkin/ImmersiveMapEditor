/// A connected part of the buffer's graph, its depths computed from its
/// rightmost edge outward, and the depth of a point from the parts already
/// done: JTS's `BufferSubgraph`, `RightmostEdgeFinder` and
/// `SubgraphDepthLocater`.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS: a part
/// with no forward edge fails (JTS asserts), and the depth locator skips a
/// part or an edge whose envelope lies left of the point (the same
/// segments are found).
final class BufferSubgraph {
    private let finder = RightmostEdgeFinder()
    @exclusivity(unchecked) private(set) var dirEdgeList: [GeomGraph.DirectedEdge] = []
    @exclusivity(unchecked) private(set) var nodes: [GeomGraph.Node] = []
    @exclusivity(unchecked) private(set) var rightMostCoord: Coordinate?
    @exclusivity(unchecked) private var env: Envelope?

    /// The envelope of the part's edges (each edge's last point left out:
    /// it is the first of another).
    func getEnvelope() -> Envelope {
        if let env { return env }
        var e = Envelope()
        for de in dirEdgeList {
            let pts = de.edge.pts
            for i in 0..<(pts.count - 1) { e.expandToInclude(pts[i]) }
        }
        env = e
        return e
    }

    /// The part reachable from a node, and its rightmost edge.
    func create(_ node: GeomGraph.Node) throws {
        addReachable(node)
        try finder.findEdge(dirEdgeList)
        rightMostCoord = finder.minCoord
    }

    private func addReachable(_ startNode: GeomGraph.Node) {
        var nodeStack = [startNode]
        while let node = nodeStack.popLast() { add(node, &nodeStack) }
    }

    private func add(_ node: GeomGraph.Node, _ nodeStack: inout [GeomGraph.Node]) {
        node.isVisited = true
        nodes.append(node)
        for de in node.edges.edges {
            dirEdgeList.append(de)
            let symNode = de.sym.node!
            if !symNode.isVisited { nodeStack.append(symNode) }
        }
    }

    /// The depths of every edge, from the depth outside the rightmost one.
    func computeDepth(_ outsideDepth: Int) throws {
        for de in dirEdgeList { de.isVisited = false }
        let de = finder.orientedDe!
        try de.setEdgeDepths(Position.right, outsideDepth)
        try copySymDepths(de)
        try computeDepths(de)
    }

    /// Breadth first from the start edge's node, each node's edges from one
    /// whose depths are known.
    private func computeDepths(_ startEdge: GeomGraph.DirectedEdge) throws {
        var nodesVisited = Set<ObjectIdentifier>()
        var nodeQueue: [GeomGraph.Node] = []
        var head = 0
        let startNode = startEdge.node!
        nodeQueue.append(startNode)
        nodesVisited.insert(ObjectIdentifier(startNode))
        startEdge.isVisited = true
        while head < nodeQueue.count {
            let n = nodeQueue[head]
            head += 1
            nodesVisited.insert(ObjectIdentifier(n))
            try computeNodeDepth(n)
            for de in n.edges.edges {
                let sym = de.sym!
                if sym.isVisited { continue }
                let adjNode = sym.node!
                if nodesVisited.insert(ObjectIdentifier(adjNode)).inserted { nodeQueue.append(adjNode) }
            }
        }
    }

    private func computeNodeDepth(_ n: GeomGraph.Node) throws {
        guard let startEdge = n.edges.edges.first(where: { $0.isVisited || $0.sym.isVisited }) else {
            throw TopologyException("unable to find edge to compute depths at", n.getCoordinate())
        }
        try n.edges.computeDepths(startEdge)
        for de in n.edges.edges {
            de.isVisited = true
            try copySymDepths(de)
        }
    }

    private func copySymDepths(_ de: GeomGraph.DirectedEdge) throws {
        let sym = de.sym!
        try sym.setDepth(Position.left, de.getDepth(Position.right))
        try sym.setDepth(Position.right, de.getDepth(Position.left))
    }

    /// Marks the edges with the inside on their right and the outside on
    /// their left: the boundary of the buffer.
    func findResultEdges() {
        for de in dirEdgeList
        where de.getDepth(Position.right) >= 1 && de.getDepth(Position.left) <= 0 && !de.isInteriorAreaEdge() {
            de.isInResult = true
        }
    }

    /// The order of the parts: by the x of their rightmost coordinates.
    func compareTo(_ graph: BufferSubgraph) -> Int {
        if rightMostCoord!.x < graph.rightMostCoord!.x { return -1 }
        if rightMostCoord!.x > graph.rightMostCoord!.x { return 1 }
        return 0
    }
}

/// The edge of a part of the graph at its rightmost coordinate, directed so
/// the outside is on its right.
final class RightmostEdgeFinder {
    @exclusivity(unchecked) private var minIndex = -1
    @exclusivity(unchecked) private(set) var minCoord: Coordinate?
    @exclusivity(unchecked) private var minDe: GeomGraph.DirectedEdge?
    @exclusivity(unchecked) private(set) var orientedDe: GeomGraph.DirectedEdge?

    func findEdge(_ dirEdgeList: [GeomGraph.DirectedEdge]) throws {
        // The rightmost point of the forward edges.
        for de in dirEdgeList where de.isForward { checkForRightmostCoordinate(de) }
        guard minDe != nil else { throw TopologyException("No forward edges found in buffer subgraph") }
        // At a node, the rightmost edge there; inside an edge, the segment
        // whose side faces right.
        if minIndex == 0 {
            findRightmostEdgeAtNode()
        } else {
            findRightmostEdgeAtVertex()
        }
        orientedDe = minDe
        let rightmostSide = getRightmostSide(minDe!, minIndex)
        if rightmostSide == Position.left { orientedDe = minDe!.sym }
    }

    private func findRightmostEdgeAtNode() {
        let node = minDe!.node!
        minDe = node.edges.getRightmostEdge()
        if !minDe!.isForward {
            minDe = minDe!.sym
            minIndex = minDe!.edge.pts.count - 1
        }
    }

    private func findRightmostEdgeAtVertex() {
        let pts = minDe!.edge.pts
        let minCoord = minCoord!
        let pPrev = pts[minIndex - 1]
        let pNext = pts[minIndex + 1]
        let orientation = Orientation.index(minCoord, pNext, pPrev)
        var usePrev = false
        if pPrev.y < minCoord.y && pNext.y < minCoord.y && orientation == Orientation.counterclockwise {
            usePrev = true
        } else if pPrev.y > minCoord.y && pNext.y > minCoord.y && orientation == Orientation.clockwise {
            usePrev = true
        }
        if usePrev { minIndex -= 1 }
    }

    private func checkForRightmostCoordinate(_ de: GeomGraph.DirectedEdge) {
        let coord = de.edge.pts
        for i in 0..<(coord.count - 1) where minCoord == nil || coord[i].x > minCoord!.x {
            minDe = de
            minIndex = i
            minCoord = coord[i]
        }
    }

    private func getRightmostSide(_ de: GeomGraph.DirectedEdge, _ index: Int) -> Int {
        var side = getRightmostSideOfSegment(de, index)
        if side < 0 { side = getRightmostSideOfSegment(de, index - 1) }
        if side < 0 {
            // Both segments are horizontal: look again (as JTS and GEOS do).
            minCoord = nil
            checkForRightmostCoordinate(de)
        }
        return side
    }

    private func getRightmostSideOfSegment(_ de: GeomGraph.DirectedEdge, _ i: Int) -> Int {
        let coord = de.edge.pts
        if i < 0 || i + 1 >= coord.count { return -1 }
        if coord[i].y == coord[i + 1].y { return -1 }
        return coord[i].y < coord[i + 1].y ? Position.right : Position.left
    }
}

/// The depth of a point: the left depth of the nearest segment a ray to its
/// right crosses, among the parts done so far.
struct SubgraphDepthLocater {
    let subgraphs: [BufferSubgraph]

    func getDepth(_ p: Coordinate) -> Int {
        let stabbedSegments = findStabbedSegments(p)
        guard var min = stabbedSegments.first else { return 0 }
        for ds in stabbedSegments.dropFirst() where ds.compareTo(min) < 0 { min = ds }
        return min.leftDepth
    }

    private func findStabbedSegments(_ stabbingRayLeftPt: Coordinate) -> [DepthSegment] {
        var stabbedSegments: [DepthSegment] = []
        for bsg in subgraphs {
            let env = bsg.getEnvelope()
            if stabbingRayLeftPt.y < env.minY || stabbingRayLeftPt.y > env.maxY || stabbingRayLeftPt.x > env.maxX { continue }
            for de in bsg.dirEdgeList where de.isForward {
                let env = de.edge.getEnvelope()
                if stabbingRayLeftPt.y < env.minY || stabbingRayLeftPt.y > env.maxY || stabbingRayLeftPt.x > env.maxX { continue }
                findStabbedSegments(stabbingRayLeftPt, de, &stabbedSegments)
            }
        }
        return stabbedSegments
    }

    private func findStabbedSegments(_ stabbingRayLeftPt: Coordinate, _ dirEdge: GeomGraph.DirectedEdge,
                                     _ stabbedSegments: inout [DepthSegment]) {
        let pts = dirEdge.edge.pts
        for i in 0..<(pts.count - 1) {
            var low = pts[i], high = pts[i + 1]
            var swapped = false
            if low.y > high.y {
                swap(&low, &high)
                swapped = true
            }
            let maxx = cxxMax(low.x, high.x)
            if maxx < stabbingRayLeftPt.x { continue }
            if low.y == high.y { continue }
            if stabbingRayLeftPt.y < low.y || stabbingRayLeftPt.y > high.y { continue }
            if Orientation.index(low, high, stabbingRayLeftPt) == Orientation.right { continue }
            let depth = swapped ? dirEdge.getDepth(Position.right) : dirEdge.getDepth(Position.left)
            stabbedSegments.append(DepthSegment(LineSegment(low, high), depth))
        }
    }

    /// A segment pointing up, with the depth on its left, ordered so the
    /// smallest is the nearest to a ray's start.
    struct DepthSegment {
        let upwardSeg: LineSegment
        let leftDepth: Int

        init(_ seg: LineSegment, _ depth: Int) {
            upwardSeg = seg
            leftDepth = depth
        }

        func compareTo(_ other: DepthSegment) -> Int {
            if upwardSeg.minX >= other.upwardSeg.maxX
                || upwardSeg.maxX <= other.upwardSeg.minX
                || upwardSeg.minY >= other.upwardSeg.maxY
                || upwardSeg.maxY <= other.upwardSeg.minY {
                return upwardSeg.compareTo(other.upwardSeg)
            }
            var orientIndex = upwardSeg.orientationIndex(other.upwardSeg)
            if orientIndex == 0 { orientIndex = -1 * other.upwardSeg.orientationIndex(upwardSeg) }
            return orientIndex
        }
    }
}
