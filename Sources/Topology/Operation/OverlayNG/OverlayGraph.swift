/// The graph of the noded edges of an overlay: every edge as a pair of
/// half-edges, the half-edges by their origin node: JTS's `OverlayGraph`.
///
/// The nodes are kept as GEOS 3.13 keeps them, in a libc++ `unordered_map`
/// keyed by GEOS's coordinate hash (`CxxUnorderedMap`), and are labelled in
/// its order: where an edge between two nodes gets conflicting locations at
/// its ends (near-degenerate input), the node labelled last decides, so the
/// order reaches the result (JTS keeps a hash map of its own order).
public final class OverlayGraph {
    @exclusivity(unchecked) public private(set) var edges: [OverlayEdge] = []
    @exclusivity(unchecked) private var nodeMap = CxxUnorderedMap<Coordinate, OverlayEdge>(hash: { $0.geosHashCode }, equal: { $0.equals2D($1) })

    public init() {}

    /// A graph with room for the edges of `edgeCount` noded edges.
    public init(capacity edgeCount: Int) {
        edges.reserveCapacity(2 * edgeCount)
        nodeMap.reserveCapacity(2 * edgeCount)
    }

    deinit {
        for e in edges { e.unlink() }
    }

    /// The edges leaving each node, one per node, in the map's order.
    public var nodeEdges: [OverlayEdge] { nodeMap.orderedIndices.map { nodeMap.values[$0] } }

    public func getNodeEdge(_ nodePt: Coordinate) -> OverlayEdge? { nodeMap.value(nodePt) }

    public func getResultAreaEdges() -> [OverlayEdge] { edges.filter(\.isInResultArea) }

    @discardableResult
    public func addEdge(_ pts: [Coordinate], _ label: OverlayLabel) throws -> OverlayEdge {
        let (e, eSym) = OverlayEdge.createEdgePair(pts, label)
        try insert(e)
        try insert(eSym)
        return e
    }

    private func insert(_ e: OverlayEdge) throws {
        edges.append(e)
        if let nodeEdge = nodeMap.value(e.orig) {
            try nodeEdge.insert(e)
        } else {
            nodeMap.insert(e.orig, e)
        }
    }
}
