/// Merges the noded edges that are the same edge (by `EdgeKey`) into the
/// first of them, keeping the order they came in: JTS's `EdgeMerger`.
enum EdgeMerger {
    static func merge(_ edges: [Edge]) throws -> [Edge] {
        var mergedEdges: [Edge] = []
        var edgeMap: [EdgeKey: Edge] = [:]
        edgeMap.reserveCapacity(edges.count)
        mergedEdges.reserveCapacity(edges.count)
        for edge in edges {
            let edgeKey = try EdgeKey(edge)
            if let baseEdge = edgeMap[edgeKey] {
                try Assert.isTrue(baseEdge.size == edge.size, "Merge of edges of different sizes - probable noding error.")
                baseEdge.merge(edge)
            } else {
                edgeMap[edgeKey] = edge
                mergedEdges.append(edge)
            }
        }
        return mergedEdges
    }
}
