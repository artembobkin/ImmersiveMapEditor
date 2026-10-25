/// The nodes of the planar graph by coordinate, and the graph of edges and
/// their directed ends: JTS's `geomgraph.Node`, `geomgraph.NodeMap` and
/// `geomgraph.PlanarGraph`, the part the buffer uses. Every node has a
/// `DirectedEdgeStar` (the old overlay's `OverlayNodeFactory`).
///
/// The nodes are in coordinate order (a `TreeMap` in JTS, a `std::map` in
/// GEOS): kept by coordinate and sorted when the graph is read.
extension GeomGraph {
    final class Node {
        let coord: Coordinate
        let edges = DirectedEdgeStar()
        @exclusivity(unchecked) var isVisited = false

        init(_ coord: Coordinate) { self.coord = coord }

        func getCoordinate() -> Coordinate { coord }

        /// Adds an end leaving the node (GEOS refuses one that does not).
        func add(_ e: DirectedEdge) throws {
            if !e.getCoordinate().equals2D(coord) {
                throw IllegalArgumentException("EdgeEnd with coordinate \(e.getCoordinate()) invalid for node \(coord)")
            }
            edges.insert(e)
            e.node = self
        }
    }

    final class PlanarGraph {
        @exclusivity(unchecked) private(set) var edges: [Edge] = []
        @exclusivity(unchecked) private(set) var edgeEndList: [DirectedEdge] = []
        @exclusivity(unchecked) private var nodeMap: [Coordinate: Node] = [:]

        func addNode(_ coord: Coordinate) -> Node {
            if let node = nodeMap[coord] { return node }
            let node = Node(coord)
            nodeMap[coord] = node
            return node
        }

        func add(_ e: DirectedEdge) throws {
            edgeEndList.append(e)
            try addNode(e.getCoordinate()).add(e)
        }

        /// Each edge with its two directed ends.
        func addEdges(_ edgesToAdd: [Edge]) throws {
            for e in edgesToAdd {
                edges.append(e)
                let de1 = DirectedEdge(e, true)
                let de2 = DirectedEdge(e, false)
                de1.sym = de2
                de2.sym = de1
                try add(de1)
                try add(de2)
            }
        }

        /// The nodes in coordinate order.
        func getNodes() -> [Node] {
            nodeMap.values.sorted { $0.coord.compareTo($1.coord) < 0 }
        }

        static func linkResultDirectedEdges(_ nodes: [Node]) throws {
            for node in nodes { try node.edges.linkResultDirectedEdges() }
        }

        /// Breaks the references between nodes, ends and rings, so they are
        /// freed with the graph.
        func dispose() {
            for de in edgeEndList {
                de.edgeRing?.breakLinks()
                de.minEdgeRing?.breakLinks()
                de.node = nil
                de.edgeRing = nil
                de.minEdgeRing = nil
            }
            nodeMap = [:]
        }
    }
}
