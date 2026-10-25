/// The end of an edge at a node, ordered around the node by its direction,
/// and the directed edge the buffer builds on: JTS's `geomgraph.EdgeEnd`
/// and `geomgraph.DirectedEdge`.
///
/// As in GEOS 3.13, an edge end of two equal points is not refused here
/// (JTS asserts it is not one).
extension GeomGraph {
    class EdgeEnd {
        let edge: Edge
        @exclusivity(unchecked) var label: Label!
        @exclusivity(unchecked) var node: Node?
        @exclusivity(unchecked) private(set) var p0 = Coordinate(0, 0)
        @exclusivity(unchecked) private(set) var p1 = Coordinate(0, 0)
        @exclusivity(unchecked) private(set) var dx = 0.0
        @exclusivity(unchecked) private(set) var dy = 0.0
        @exclusivity(unchecked) private(set) var quadrant = 0

        init(_ edge: Edge) { self.edge = edge }

        func initEnd(_ p0: Coordinate, _ p1: Coordinate) {
            self.p0 = p0
            self.p1 = p1
            dx = p1.x - p0.x
            dy = p1.y - p0.y
            quadrant = Quadrant.quadrant(dx, dy)
        }

        func getCoordinate() -> Coordinate { p0 }
        func getDirectedCoordinate() -> Coordinate { p1 }

        /// The order around the node: by quadrant, then by the side one end
        /// is of the other.
        func compareDirection(_ e: EdgeEnd) -> Int {
            if dx == e.dx && dy == e.dy { return 0 }
            if quadrant > e.quadrant { return 1 }
            if quadrant < e.quadrant { return -1 }
            return Orientation.index(e.p0, e.p1, p1)
        }

        func compareTo(_ e: EdgeEnd) -> Int { compareDirection(e) }
    }

    final class DirectedEdge: EdgeEnd {
        let isForward: Bool
        @exclusivity(unchecked) var isInResult = false
        @exclusivity(unchecked) var isVisited = false
        @exclusivity(unchecked) unowned(unsafe) var sym: DirectedEdge!
        @exclusivity(unchecked) unowned(unsafe) var next: DirectedEdge?
        @exclusivity(unchecked) unowned(unsafe) var nextMin: DirectedEdge?
        @exclusivity(unchecked) var edgeRing: EdgeRing?
        @exclusivity(unchecked) var minEdgeRing: EdgeRing?
        /// The depths on the edge, its left and its right (`Position`).
        @exclusivity(unchecked) private var depth = [0, -999, -999]

        init(_ edge: Edge, _ isForward: Bool) {
            self.isForward = isForward
            super.init(edge)
            if isForward {
                initEnd(edge.getCoordinate(0), edge.getCoordinate(1))
            } else {
                let n = edge.numPoints - 1
                initEnd(edge.getCoordinate(n), edge.getCoordinate(n - 1))
            }
            label = Label(edge.label)
            if !isForward { label.flip() }
        }

        func getDepth(_ position: Int) -> Int { depth[position] }

        func setDepth(_ position: Int, _ depthVal: Int) throws {
            if depth[position] != -999 && depth[position] != depthVal {
                throw TopologyException("assigned depths do not match", getCoordinate())
            }
            depth[position] = depthVal
        }

        func getDepthDelta() -> Int { isForward ? edge.depthDelta : -edge.depthDelta }

        /// Whether both sides of the edge are inside the area of both
        /// geometries.
        func isInteriorAreaEdge() -> Bool {
            var result = true
            for i in 0..<2 {
                if !(label.isArea(i)
                    && label.getLocation(i, Position.left) == Location.interior
                    && label.getLocation(i, Position.right) == Location.interior) {
                    result = false
                }
            }
            return result
        }

        /// Sets the depth on one side and, from the edge's depth delta, the
        /// other.
        func setEdgeDepths(_ position: Int, _ depth: Int) throws {
            var depthDelta = edge.depthDelta
            if !isForward { depthDelta = -depthDelta }
            let directionFactor = position == Position.left ? -1 : 1
            let oppositePos = Position.opposite(position)
            let delta = depthDelta * directionFactor
            let oppositeDepth = depth + delta
            try setDepth(position, depth)
            try setDepth(oppositePos, oppositeDepth)
        }
    }
}
