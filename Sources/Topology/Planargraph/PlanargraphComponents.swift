/// JTS's `planargraph` package: a graph of nodes at coordinates, edges
/// between them and the two directed edges of each edge, kept around each
/// node in angular order. The polygonizer and the line merger extend it.
///
/// Where JTS keeps the edges and directed edges of a graph in `HashSet`s
/// (identity order, random from run to run), GEOS 3.13 keeps them in
/// vectors in insertion order, and the port follows GEOS: the order decides
/// the order of the polygonizer's and the line merger's results. The nodes
/// are in coordinate order (JTS's `TreeMap`, GEOS's `std::map`), the
/// directed edges around a node sorted with libc++'s `std::sort` (JTS's
/// stable sort): equal directions (parallel edges) keep GEOS's order.
public enum Planargraph {}

extension Planargraph {
    /// The flags every component has: JTS's `GraphComponent`.
    class GraphComponent {
        @exclusivity(unchecked) var isMarked = false
        @exclusivity(unchecked) var isVisited = false
        @exclusivity(unchecked) var data: AnyObject?
    }

    /// A node: JTS's `planargraph.Node`.
    final class Node: GraphComponent {
        let pt: Coordinate
        let deStar = DirectedEdgeStar()

        init(_ pt: Coordinate) { self.pt = pt }

        func getCoordinate() -> Coordinate { pt }
        func addOutEdge(_ de: DirectedEdge) { deStar.add(de) }
        func getOutEdges() -> DirectedEdgeStar { deStar }
        func getDegree() -> Int { deStar.getDegree() }
    }

    /// An edge of two directed edges: JTS's `planargraph.Edge`.
    class Edge: GraphComponent {
        @exclusivity(unchecked) var dirEdge: [DirectedEdge] = []

        func setDirectedEdges(_ de0: DirectedEdge, _ de1: DirectedEdge) {
            dirEdge = [de0, de1]
            de0.parentEdge = self
            de1.parentEdge = self
            de0.sym = de1
            de1.sym = de0
            de0.from.addOutEdge(de0)
            de1.from.addOutEdge(de1)
        }

        func getDirEdge(_ i: Int) -> DirectedEdge { dirEdge[i] }
    }

    /// One direction of an edge, leaving a node towards a direction point:
    /// JTS's `planargraph.DirectedEdge`, ordered around its node by quadrant,
    /// then by orientation.
    class DirectedEdge: GraphComponent {
        @exclusivity(unchecked) unowned(unsafe) var parentEdge: Edge!
        unowned(unsafe) let from: Node
        unowned(unsafe) let to: Node
        let p0: Coordinate
        let p1: Coordinate
        @exclusivity(unchecked) unowned(unsafe) var sym: DirectedEdge?
        let edgeDirection: Bool
        let quadrant: Int

        init(_ from: Node, _ to: Node, _ directionPt: Coordinate, _ edgeDirection: Bool) {
            self.from = from
            self.to = to
            self.edgeDirection = edgeDirection
            p0 = from.getCoordinate()
            p1 = directionPt
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            if dx == 0 && dy == 0 {
                // GEOS's quadrant throws on a zero direction, which only an edge
                // whose ends are one node (a NaN end found as the other) gives:
                // reported as the orientation test reports it (`NonFinite`).
                NonFinite.raise()
                quadrant = Quadrant.ne
            } else {
                quadrant = Quadrant.quadrant(dx, dy)
            }
        }

        func getEdge() -> Edge { parentEdge }
        func getEdgeDirection() -> Bool { edgeDirection }
        func getFromNode() -> Node { from }
        func getToNode() -> Node { to }
        func getCoordinate() -> Coordinate { from.getCoordinate() }
        func getSym() -> DirectedEdge? { sym }

        func compareTo(_ e: DirectedEdge) -> Int { compareDirection(e) }

        func compareDirection(_ e: DirectedEdge) -> Int {
            if quadrant > e.quadrant { return 1 }
            if quadrant < e.quadrant { return -1 }
            return Orientation.index(e.p0, e.p1, p1)
        }
    }

    /// The directed edges leaving a node, sorted when read: JTS's
    /// `planargraph.DirectedEdgeStar`, sorted with libc++'s `std::sort` as
    /// GEOS sorts it.
    final class DirectedEdgeStar {
        @exclusivity(unchecked) private var outEdges: [DirectedEdge] = []
        @exclusivity(unchecked) private var sorted = false

        func add(_ de: DirectedEdge) {
            outEdges.append(de)
            sorted = false
        }

        func getDegree() -> Int { outEdges.count }

        func getEdges() -> [DirectedEdge] {
            sortEdges()
            return outEdges
        }

        private func sortEdges() {
            if !sorted {
                CxxAlgorithms.sort(&outEdges) { $0.compareTo($1) < 0 }
                sorted = true
            }
        }

        func getIndex(_ dirEdge: DirectedEdge) -> Int {
            sortEdges()
            for (i, de) in outEdges.enumerated() where de === dirEdge { return i }
            return -1
        }

        func getIndex(_ i: Int) -> Int {
            var modi = i % outEdges.count
            if modi < 0 { modi += outEdges.count }
            return modi
        }

        func getNextEdge(_ dirEdge: DirectedEdge) -> DirectedEdge {
            let i = getIndex(dirEdge)
            return outEdges[getIndex(i + 1)]
        }
    }

    /// A graph: JTS's `PlanarGraph`, its components in GEOS's orders.
    class PlanarGraph {
        @exclusivity(unchecked) private(set) var edges: [Edge] = []
        @exclusivity(unchecked) private(set) var dirEdges: [DirectedEdge] = []
        /// GEOS's `std::map` of nodes by coordinate (libc++'s tree): for
        /// finite coordinates a map by value, while a NaN coordinate finds
        /// whichever node the tree's search ends at.
        @exclusivity(unchecked) private var nodeMap = CxxTree<Coordinate, Node> { $0 < $1 }

        func findNode(_ pt: Coordinate) -> Node? { nodeMap.find(pt).map { nodeMap.nodes[$0].value } }

        func add(_ node: Node) {
            let (i, inserted) = nodeMap.insert(node.getCoordinate(), node)
            if !inserted { nodeMap.modify(i) { $0 = node } }
        }

        func add(_ edge: Edge) {
            edges.append(edge)
            dirEdges.append(edge.getDirEdge(0))
            dirEdges.append(edge.getDirEdge(1))
        }

        /// The nodes in the map's order (by coordinate).
        func getNodes() -> [Node] { nodeMap.inOrder().map { nodeMap.nodes[$0].value } }

        func findNodesOfDegree(_ degree: Int) -> [Node] { getNodes().filter { $0.getDegree() == degree } }
    }
}
