/// The directed edges leaving a node, in order around it, and the linking
/// and depth computations done over them: JTS's `geomgraph.EdgeEndStar` and
/// `geomgraph.DirectedEdgeStar`, the part the buffer uses.
///
/// JTS keeps the ends in a `TreeMap` (an equal end inserted later replaces
/// the value), GEOS 3.13 in a `std::set` (an equal end inserted later is
/// left out): the port keeps the first, as GEOS. An end left out still has
/// its node set (GEOS's `Node::add`).
extension GeomGraph {
    final class DirectedEdgeStar {
        @exclusivity(unchecked) private(set) var edges: [DirectedEdge] = []
        @exclusivity(unchecked) private var resultAreaEdgeList: [DirectedEdge]?

        /// Inserts an end in its place around the node, unless an end of the
        /// same direction is there.
        func insert(_ de: DirectedEdge) {
            var lo = 0, hi = edges.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if edges[mid].compareTo(de) < 0 { lo = mid + 1 } else { hi = mid }
            }
            if lo < edges.count && !(de.compareTo(edges[lo]) < 0) { return }
            edges.insert(de, at: lo)
        }

        func getCoordinate() -> Coordinate { edges.first?.getCoordinate() ?? .null }

        func getOutgoingDegree(_ er: EdgeRing) -> Int {
            var degree = 0
            for de in edges where de.edgeRing === er { degree += 1 }
            return degree
        }

        /// The edge whose side faces right at the node: the first or the
        /// last around it, whichever is not horizontal when they lie on
        /// both sides. Nil when neither fits (JTS asserts; GEOS returns null).
        func getRightmostEdge() -> DirectedEdge? {
            guard let de0 = edges.first else { return nil }
            if edges.count == 1 { return de0 }
            let deLast = edges[edges.count - 1]
            let quad0 = de0.quadrant, quad1 = deLast.quadrant
            if Quadrant.isNorthern(quad0) && Quadrant.isNorthern(quad1) { return de0 }
            if !Quadrant.isNorthern(quad0) && !Quadrant.isNorthern(quad1) { return deLast }
            if de0.dy != 0 { return de0 }
            if deLast.dy != 0 { return deLast }
            return nil
        }

        private func getResultAreaEdges() -> [DirectedEdge] {
            if let resultAreaEdgeList { return resultAreaEdgeList }
            let list = edges.filter { $0.isInResult || $0.sym.isInResult }
            resultAreaEdgeList = list
            return list
        }

        /// Links each incoming result edge to the next outgoing one.
        func linkResultDirectedEdges() throws {
            let list = getResultAreaEdges()
            var firstOut: DirectedEdge?
            var incoming: DirectedEdge?
            var linking = false
            for nextOut in list {
                if !nextOut.label.isArea() { continue }
                let nextIn = nextOut.sym!
                if firstOut == nil && nextOut.isInResult { firstOut = nextOut }
                if !linking {
                    if !nextIn.isInResult { continue }
                    incoming = nextIn
                    linking = true
                } else {
                    if !nextOut.isInResult { continue }
                    incoming!.next = nextOut
                    linking = false
                }
            }
            if linking {
                guard let firstOut else { throw TopologyException("no outgoing dirEdge found", getCoordinate()) }
                incoming!.next = firstOut
            }
        }

        /// Links the edges of one maximal ring into minimal rings.
        func linkMinimalDirectedEdges(_ er: EdgeRing) {
            let list = resultAreaEdgeList ?? []
            var firstOut: DirectedEdge?
            var incoming: DirectedEdge?
            var linking = false
            for nextOut in list.reversed() {
                let nextIn = nextOut.sym!
                if firstOut == nil && nextOut.edgeRing === er { firstOut = nextOut }
                if !linking {
                    if nextIn.edgeRing !== er { continue }
                    incoming = nextIn
                    linking = true
                } else {
                    if nextOut.edgeRing !== er { continue }
                    incoming!.nextMin = nextOut
                    linking = false
                }
            }
            if linking { incoming!.nextMin = firstOut }
        }

        /// The place of the end of the same direction (GEOS's `std::set::find`).
        func findIndex(_ eSearch: DirectedEdge) -> Int? {
            var lo = 0, hi = edges.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if edges[mid].compareTo(eSearch) < 0 { lo = mid + 1 } else { hi = mid }
            }
            if lo < edges.count && !(eSearch.compareTo(edges[lo]) < 0) { return lo }
            return nil
        }

        /// The depths of every edge around the node, from those of one.
        func computeDepths(_ de: DirectedEdge) throws {
            let edgeIndex = findIndex(de)!
            let startDepth = de.getDepth(Position.left)
            let targetLastDepth = de.getDepth(Position.right)
            let nextDepth = try computeDepths(edgeIndex + 1, edges.count, startDepth)
            let lastDepth = try computeDepths(0, edgeIndex, nextDepth)
            if lastDepth != targetLastDepth { throw TopologyException("depth mismatch at ", de.getCoordinate()) }
        }

        private func computeDepths(_ startIndex: Int, _ endIndex: Int, _ startDepth: Int) throws -> Int {
            var currDepth = startDepth
            for i in stride(from: startIndex, to: endIndex, by: 1) {
                let nextDe = edges[i]
                try nextDe.setEdgeDepths(Position.right, currDepth)
                currDepth = nextDe.getDepth(Position.left)
            }
            return currDepth
        }
    }
}
