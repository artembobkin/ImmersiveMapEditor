/// An edge of the planar graph and the list of unique edges: JTS's
/// `geomgraph.Edge` and `geomgraph.EdgeList`, the part the buffer uses (no
/// intersection list, monotone chains or depth: the buffer labels its edges
/// by the change of depth across them).
extension GeomGraph {
    final class Edge {
        let pts: [Coordinate]
        @exclusivity(unchecked) var label: Label
        /// The change of depth from the edge's right to its left.
        @exclusivity(unchecked) var depthDelta = 0
        @exclusivity(unchecked) var isInResult = false
        @exclusivity(unchecked) private var env: Envelope?

        init(_ pts: [Coordinate], _ label: Label) {
            self.pts = pts
            self.label = label
        }

        var numPoints: Int { pts.count }
        func getCoordinate(_ i: Int) -> Coordinate { pts[i] }

        func getEnvelope() -> Envelope {
            if let env { return env }
            var e = Envelope()
            for p in pts { e.expandToInclude(p) }
            env = e
            return e
        }

        /// The same points in the same order.
        func isPointwiseEqual(_ e: Edge) -> Bool {
            if pts.count != e.pts.count { return false }
            for i in pts.indices where !pts[i].equals2D(e.pts[i]) { return false }
            return true
        }
    }

    /// The edges of a graph, with the edge equal to a given one (the same
    /// points in either direction) found at once.
    final class EdgeList {
        @exclusivity(unchecked) private(set) var edges: [Edge] = []
        @exclusivity(unchecked) private var ocaMap: [OrientedKey: Edge] = [:]

        func add(_ e: Edge) {
            edges.append(e)
            ocaMap[OrientedKey(e.pts)] = e
        }

        func findEqualEdge(_ e: Edge) -> Edge? { ocaMap[OrientedKey(e.pts)] }
    }

    /// A coordinate array as a key equal to its reverse: equal when
    /// `OrientedCoordinateArray` compares them equal.
    struct OrientedKey: Hashable {
        let oca: OrientedCoordinateArray

        init(_ pts: [Coordinate]) { oca = OrientedCoordinateArray(pts) }

        static func == (a: OrientedKey, b: OrientedKey) -> Bool { a.oca.compareTo(b.oca) == 0 }

        func hash(into h: inout Hasher) {
            // The same for both directions: the count and the ends, unordered.
            let pts = oca.pts
            h.combine(pts.count)
            guard let first = pts.first, let last = pts.last else { return }
            if first.compareTo(last) <= 0 {
                h.combine(first)
                h.combine(last)
            } else {
                h.combine(last)
                h.combine(first)
            }
        }
    }
}
