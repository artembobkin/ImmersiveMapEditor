/// The polygons of the result edges of a planar graph: JTS's old overlay
/// (`operation.overlay`) `PolygonBuilder`, `MaximalEdgeRing` and
/// `MinimalEdgeRing`, which the buffer still uses (the overlays themselves
/// are OverlayNG's). Under the namespace `Overlay`, as their names clash
/// with OverlayNG's.
///
/// Where GEOS 3.13 differs from JTS 1.20, the port follows GEOS: a hole is
/// placed in a shell by a point not on the shell located with an indexed
/// point-in-area locator built once per shell (JTS tests the point against
/// the ring, with the same answer), and a list of minimal rings with two
/// shells throws a topology failure (JTS asserts).
public enum Overlay {}

extension Overlay {
    final class MaximalEdgeRing: GeomGraph.EdgeRing {
        override func getNext(_ de: GeomGraph.DirectedEdge) -> GeomGraph.DirectedEdge? { de.next }
        override func setEdgeRing(_ de: GeomGraph.DirectedEdge, _ er: GeomGraph.EdgeRing) { de.edgeRing = er }

        func linkDirectedEdgesForMinimalEdgeRings() {
            var de = startDe
            repeat {
                de.node!.edges.linkMinimalDirectedEdges(self)
                de = de.next!
            } while de !== startDe
        }

        func buildMinimalRings() throws -> [MinimalEdgeRing] {
            var minEdgeRings: [MinimalEdgeRing] = []
            var de = startDe
            repeat {
                if de.minEdgeRing == nil { minEdgeRings.append(try MinimalEdgeRing(de, geometryFactory)) }
                de = de.next!
            } while de !== startDe
            return minEdgeRings
        }
    }

    final class MinimalEdgeRing: GeomGraph.EdgeRing {
        override func getNext(_ de: GeomGraph.DirectedEdge) -> GeomGraph.DirectedEdge? { de.nextMin }
        override func setEdgeRing(_ de: GeomGraph.DirectedEdge, _ er: GeomGraph.EdgeRing) { de.minEdgeRing = er }
    }

    final class PolygonBuilder {
        private let geometryFactory: GeometryFactory
        @exclusivity(unchecked) private var shellList: [GeomGraph.EdgeRing] = []

        init(_ geometryFactory: GeometryFactory) { self.geometryFactory = geometryFactory }

        /// Adds the rings of a set of directed edges and their nodes.
        func add(_ dirEdges: [GeomGraph.DirectedEdge], _ nodes: [GeomGraph.Node]) throws {
            try GeomGraph.PlanarGraph.linkResultDirectedEdges(nodes)
            let maxEdgeRings = try buildMaximalEdgeRings(dirEdges)
            var freeHoleList: [GeomGraph.EdgeRing] = []
            let edgeRings = try buildMinimalEdgeRings(maxEdgeRings, &freeHoleList)
            sortShellsAndHoles(edgeRings, &freeHoleList)
            let locators = shellList.map { IndexedPointInAreaLocator($0.ring) }
            try placeFreeHoles(locators, freeHoleList)
        }

        func getPolygons() -> [Polygon] { shellList.map { $0.toPolygon(geometryFactory) } }

        private func buildMaximalEdgeRings(_ dirEdges: [GeomGraph.DirectedEdge]) throws -> [MaximalEdgeRing] {
            var maxEdgeRings: [MaximalEdgeRing] = []
            for de in dirEdges where de.isInResult && de.label.isArea() && de.edgeRing == nil {
                let er = try MaximalEdgeRing(de, geometryFactory)
                maxEdgeRings.append(er)
                er.setInResult()
            }
            return maxEdgeRings
        }

        private func buildMinimalEdgeRings(_ maxEdgeRings: [MaximalEdgeRing],
                                           _ freeHoleList: inout [GeomGraph.EdgeRing]) throws -> [GeomGraph.EdgeRing] {
            var edgeRings: [GeomGraph.EdgeRing] = []
            for er in maxEdgeRings {
                if er.getMaxNodeDegree() > 2 {
                    er.linkDirectedEdgesForMinimalEdgeRings()
                    let minEdgeRings = try er.buildMinimalRings()
                    if let shell = try findShell(minEdgeRings) {
                        for hole in minEdgeRings where hole.isHole { hole.setShell(shell) }
                        shellList.append(shell)
                    } else {
                        freeHoleList.append(contentsOf: minEdgeRings as [GeomGraph.EdgeRing])
                    }
                } else {
                    edgeRings.append(er)
                }
            }
            return edgeRings
        }

        private func findShell(_ minEdgeRings: [MinimalEdgeRing]) throws -> GeomGraph.EdgeRing? {
            var shellCount = 0
            var shell: GeomGraph.EdgeRing?
            for er in minEdgeRings where !er.isHole {
                shell = er
                shellCount += 1
            }
            if shellCount > 1 { throw TopologyException("found two shells in MinimalEdgeRing list") }
            return shell
        }

        private func sortShellsAndHoles(_ edgeRings: [GeomGraph.EdgeRing], _ freeHoleList: inout [GeomGraph.EdgeRing]) {
            for er in edgeRings {
                if er.isHole { freeHoleList.append(er) } else { shellList.append(er) }
            }
        }

        private func placeFreeHoles(_ locators: [IndexedPointInAreaLocator], _ freeHoleList: [GeomGraph.EdgeRing]) throws {
            for hole in freeHoleList where hole.shell == nil {
                guard let shell = findEdgeRingContaining(hole, locators) else {
                    throw TopologyException("unable to assign hole to a shell")
                }
                hole.setShell(shell)
            }
        }

        /// The smallest shell holding the ring, by envelope and by a point
        /// of the ring not on the shell.
        private func findEdgeRingContaining(_ testEr: GeomGraph.EdgeRing, _ locators: [IndexedPointInAreaLocator]) -> GeomGraph.EdgeRing? {
            let testRing = testEr.ring!
            let testEnv = testRing.getEnvelopeInternal()
            var minShell: GeomGraph.EdgeRing?
            var minShellEnv: Envelope?
            for (i, tryShell) in shellList.enumerated() {
                let tryShellRing = tryShell.ring!
                let tryShellEnv = tryShellRing.getEnvelopeInternal()
                if tryShellEnv == testEnv { continue }
                if !tryShellEnv.contains(testEnv) { continue }
                let testPt = CoordinateArrays.ptNotInList(testRing.points, tryShellRing.points) ?? .null
                if locators[i].locate(testPt) != Location.exterior {
                    if minShell == nil || minShellEnv!.contains(tryShellEnv) {
                        minShell = tryShell
                        minShellEnv = tryShellEnv
                    }
                }
            }
            return minShell
        }
    }
}
