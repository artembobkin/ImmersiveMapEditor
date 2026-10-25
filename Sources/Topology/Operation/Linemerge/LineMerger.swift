/// Merges lines that meet end to end at nodes of degree 2 into maximal
/// lines: JTS's `LineMerger` (with `LineMergeGraph`, `LineMergeEdge`,
/// `LineMergeDirectedEdge` and `EdgeString`), as GEOS 3.13 runs it
/// (`GEOSLineMerge`): the nodes in coordinate order, the edges around a
/// node in GEOS's order (see `Planargraph`), and GEOS's directed mode.
public final class LineMerger {
    final class LineMergeEdge: Planargraph.Edge {
        let line: LineString
        init(_ line: LineString) { self.line = line }
    }

    final class LineMergeDirectedEdge: Planargraph.DirectedEdge {
        /// The directed edge continuing this one through a node of degree
        /// 2, if there is one (and, checking direction, it runs forward).
        func getNext(_ checkDirection: Bool) throws -> LineMergeDirectedEdge? {
            let toNode = getToNode()
            if toNode.getDegree() != 2 { return nil }
            let edges = toNode.getOutEdges().getEdges()
            let nextEdge: Planargraph.DirectedEdge
            if edges[0] === getSym() {
                nextEdge = edges[1]
            } else {
                try Assert.isTrue(edges[1] === getSym())
                nextEdge = edges[0]
            }
            let next = unsafeDowncast(nextEdge, to: LineMergeDirectedEdge.self)
            return !checkDirection || next.getEdgeDirection() ? next : nil
        }

        var line: LineString { unsafeDowncast(parentEdge, to: LineMergeEdge.self).line }
    }

    final class LineMergeGraph: Planargraph.PlanarGraph {
        func addEdge(_ lineString: LineString) {
            if lineString.isEmpty() { return }
            let coordinates = CoordinateArrays.removeRepeatedPoints(lineString.points)
            if coordinates.count <= 1 { return }
            let startNode = getNode(coordinates[0])
            let endNode = getNode(coordinates[coordinates.count - 1])
            let de0 = LineMergeDirectedEdge(startNode, endNode, coordinates[1], true)
            let de1 = LineMergeDirectedEdge(endNode, startNode, coordinates[coordinates.count - 2], false)
            let edge = LineMergeEdge(lineString)
            edge.setDirectedEdges(de0, de1)
            add(edge)
        }

        private func getNode(_ coordinate: Coordinate) -> Planargraph.Node {
            if let node = findNode(coordinate) { return node }
            let node = Planargraph.Node(coordinate)
            add(node)
            return node
        }
    }

    /// A sequence of directed edges merged into one line: JTS's `EdgeString`.
    struct EdgeString {
        let factory: GeometryFactory
        var directedEdges: [LineMergeDirectedEdge] = []

        /// The line, reversed when most of its edges run backwards.
        func toLineString() -> LineString {
            var forwardDirectedEdges = 0, reverseDirectedEdges = 0
            var coordinates = CoordinateList()
            for de in directedEdges {
                if de.getEdgeDirection() { forwardDirectedEdges += 1 } else { reverseDirectedEdges += 1 }
                coordinates.add(de.line.points, false, de.getEdgeDirection())
            }
            var pts = coordinates.points
            if reverseDirectedEdges > forwardDirectedEdges { pts.reverse() }
            return factory.createLineString(pts)
        }
    }

    let graph = LineMergeGraph()
    let isDirected: Bool
    @exclusivity(unchecked) var factory: GeometryFactory?
    @exclusivity(unchecked) var edgeStrings: [EdgeString] = []
    @exclusivity(unchecked) var mergedLineStrings: [LineString] = []

    public init(_ directed: Bool = false) {
        isDirected = directed
    }

    /// Adds the linear components of a geometry.
    public func add(_ geometry: Geometry) {
        geometry.applyComponents { c in
            if let line = c as? LineString {
                if factory == nil { factory = line.factory }
                graph.addEdge(line)
            }
        }
    }

    public func add(_ geometries: [Geometry]) {
        for g in geometries { add(g) }
    }

    private func merge() throws {
        if !mergedLineStrings.isEmpty { return }
        for n in graph.getNodes() { n.isMarked = false }
        for e in graph.edges { e.isMarked = false }
        edgeStrings = []
        try buildEdgeStringsForNonDegree2Nodes()
        try buildEdgeStringsForUnprocessedNodes()
        mergedLineStrings = edgeStrings.map { $0.toLineString() }
    }

    /// The isolated loops: every node not yet visited has degree 2.
    private func buildEdgeStringsForUnprocessedNodes() throws {
        for node in graph.getNodes() where !node.isMarked {
            try Assert.isTrue(node.getDegree() == 2)
            try buildEdgeStringsStartingAt(node)
            node.isMarked = true
        }
    }

    /// The obvious starts: the nodes not of degree 2 (and in the directed
    /// mode those where both edges run the same way).
    private func buildEdgeStringsForNonDegree2Nodes() throws {
        for node in graph.getNodes() {
            var isStartNode = node.getDegree() != 2
            if !isStartNode && isDirected {
                let edges = node.getOutEdges().getEdges()
                isStartNode = edges[0].getEdgeDirection() == edges[1].getEdgeDirection()
            }
            if isStartNode {
                try buildEdgeStringsStartingAt(node)
                node.isMarked = true
            }
        }
    }

    private func buildEdgeStringsStartingAt(_ node: Planargraph.Node) throws {
        for de in node.getOutEdges().getEdges() {
            let directedEdge = unsafeDowncast(de, to: LineMergeDirectedEdge.self)
            if isDirected && !directedEdge.getEdgeDirection() { continue }
            if directedEdge.getEdge().isMarked { continue }
            edgeStrings.append(try buildEdgeStringStartingWith(directedEdge))
        }
    }

    private func buildEdgeStringStartingWith(_ start: LineMergeDirectedEdge) throws -> EdgeString {
        var edgeString = EdgeString(factory: factory!)
        var current: LineMergeDirectedEdge? = start
        repeat {
            edgeString.directedEdges.append(current!)
            current!.getEdge().isMarked = true
            current = try current!.getNext(isDirected)
        } while current != nil && current !== start
        return edgeString
    }

    public func getMergedLineStrings() throws -> [LineString] {
        try merge()
        let ret = mergedLineStrings
        mergedLineStrings = []
        return ret
    }
}

extension Geometry {
    /// The lines of the geometry merged end to end (`GEOSLineMerge`): the
    /// merged lines built into the smallest geometry that holds them.
    public func lineMerge(factory: GeometryFactory = .default) throws -> Geometry {
        let merger = LineMerger()
        merger.add(self)
        return factory.buildGeometry(try NonFinite.scope { try merger.getMergedLineStrings() })
    }
}
