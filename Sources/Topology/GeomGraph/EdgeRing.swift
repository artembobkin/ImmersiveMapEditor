/// A ring of directed edges of the graph, a shell or a hole: JTS's
/// `geomgraph.EdgeRing`, followed by `next` (a maximal ring) or `nextMin`
/// (a minimal ring), as its subclasses in `Overlay` say.
///
/// As in GEOS 3.13, an edge of the ring is not asserted to be an area edge.
extension GeomGraph {
    class EdgeRing {
        let startDe: DirectedEdge
        let geometryFactory: GeometryFactory
        @exclusivity(unchecked) private var maxNodeDegree = -1
        @exclusivity(unchecked) private(set) var edges: [DirectedEdge] = []
        @exclusivity(unchecked) private var pts: [Coordinate] = []
        let label = Label(Location.none)
        @exclusivity(unchecked) private(set) var ring: LinearRing!
        @exclusivity(unchecked) private(set) var isHole = false
        @exclusivity(unchecked) private(set) var shell: EdgeRing?
        @exclusivity(unchecked) private(set) var holes: [EdgeRing] = []

        /// The ring from its start, its points and orientation computed.
        init(_ start: DirectedEdge, _ geometryFactory: GeometryFactory) throws {
            startDe = start
            self.geometryFactory = geometryFactory
            try computePoints(start)
            computeRing()
        }

        func getNext(_ de: DirectedEdge) -> DirectedEdge? { fatalError("abstract") }
        func setEdgeRing(_ de: DirectedEdge, _ er: EdgeRing) { fatalError("abstract") }

        var isShell: Bool { shell == nil }

        func setShell(_ shell: EdgeRing?) {
            self.shell = shell
            shell?.holes.append(self)
        }

        func getCoordinate(_ i: Int) -> Coordinate { pts[i] }

        /// Drops the links between shells and holes, so the rings are freed.
        func breakLinks() {
            shell = nil
            holes = []
        }

        func toPolygon(_ geometryFactory: GeometryFactory) -> Polygon {
            geometryFactory.createPolygon(ring, holes.map { $0.ring })
        }

        private func computeRing() {
            ring = geometryFactory.createLinearRing(pts)
            isHole = Orientation.isCCW(ring.points)
        }

        private func computePoints(_ start: DirectedEdge) throws {
            var de: DirectedEdge? = start
            var isFirstEdge = true
            repeat {
                guard let d = de else { throw TopologyException("EdgeRing::computePoints: found null Directed Edge") }
                if d.edgeRing === self {
                    throw TopologyException("Directed Edge visited twice during ring-building", d.getCoordinate())
                }
                edges.append(d)
                mergeLabel(d.label)
                addPoints(d.edge, d.isForward, isFirstEdge)
                isFirstEdge = false
                setEdgeRing(d, self)
                de = getNext(d)
            } while de !== startDe
        }

        func getMaxNodeDegree() -> Int {
            if maxNodeDegree < 0 { computeMaxNodeDegree() }
            return maxNodeDegree
        }

        private func computeMaxNodeDegree() {
            maxNodeDegree = 0
            var de = startDe
            repeat {
                let degree = de.node!.edges.getOutgoingDegree(self)
                if degree > maxNodeDegree { maxNodeDegree = degree }
                de = getNext(de)!
            } while de !== startDe
            maxNodeDegree *= 2
        }

        func setInResult() {
            var de = startDe
            repeat {
                de.edge.isInResult = true
                de = de.next!
            } while de !== startDe
        }

        private func mergeLabel(_ deLabel: Label) {
            mergeLabel(deLabel, 0)
            mergeLabel(deLabel, 1)
        }

        private func mergeLabel(_ deLabel: Label, _ geomIndex: Int) {
            let loc = deLabel.getLocation(geomIndex, Position.right)
            if loc == Location.none { return }
            if label.getLocation(geomIndex) == Location.none { label.setLocation(geomIndex, loc) }
        }

        private func addPoints(_ edge: Edge, _ isForward: Bool, _ isFirstEdge: Bool) {
            let edgePts = edge.pts
            if isForward {
                pts.append(contentsOf: edgePts[(isFirstEdge ? 0 : 1)...])
            } else {
                let startIndex = isFirstEdge ? edgePts.count - 1 : edgePts.count - 2
                if startIndex >= 0 { pts.append(contentsOf: edgePts[0...startIndex].reversed()) }
            }
        }
    }
}
