/// The graph the polygonizer builds from its lines, and its parts: JTS's
/// `PolygonizeGraph`, `PolygonizeEdge` and `PolygonizeDirectedEdge`, with
/// GEOS 3.13's orders (see `Planargraph`) and its de-duplicated dangles.
public enum Polygonize {}

extension Polygonize {
    final class PolygonizeEdge: Planargraph.Edge {
        let line: LineString
        init(_ line: LineString) { self.line = line }
    }

    final class PolygonizeDirectedEdge: Planargraph.DirectedEdge {
        @exclusivity(unchecked) unowned(unsafe) var edgeRing: EdgeRing?
        @exclusivity(unchecked) unowned(unsafe) var next: PolygonizeDirectedEdge?
        @exclusivity(unchecked) var label = -1

        var isInRing: Bool { edgeRing != nil }
        var pSym: PolygonizeDirectedEdge { unsafeDowncast(sym!, to: PolygonizeDirectedEdge.self) }
        var line: LineString { unsafeDowncast(parentEdge, to: PolygonizeEdge.self).line }
    }

    final class PolygonizeGraph: Planargraph.PlanarGraph {
        /// Every edge ring made, kept alive here (the directed edges refer
        /// to theirs unowned).
        @exclusivity(unchecked) var edgeRings: [EdgeRing] = []
        let factory: GeometryFactory

        init(_ factory: GeometryFactory) { self.factory = factory }

        static func pde(_ de: Planargraph.DirectedEdge) -> PolygonizeDirectedEdge {
            unsafeDowncast(de, to: PolygonizeDirectedEdge.self)
        }

        static func getDegreeNonDeleted(_ node: Planargraph.Node) -> Int {
            var degree = 0
            for de in node.getOutEdges().getEdges() where !de.isMarked { degree += 1 }
            return degree
        }

        static func getDegree(_ node: Planargraph.Node, _ label: Int) -> Int {
            var degree = 0
            for de in node.getOutEdges().getEdges() where pde(de).label == label { degree += 1 }
            return degree
        }

        /// Marks every edge of a node deleted.
        static func deleteAllEdges(_ node: Planargraph.Node) {
            for de in node.getOutEdges().getEdges() {
                de.isMarked = true
                de.sym?.isMarked = true
            }
        }

        func addEdge(_ line: LineString) {
            if line.isEmpty() { return }
            let linePts = CoordinateArrays.removeRepeatedPoints(line.points)
            if linePts.count < 2 { return }
            let startPt = linePts[0]
            let endPt = linePts[linePts.count - 1]
            let nStart = getNode(startPt)
            let nEnd = getNode(endPt)
            let de0 = PolygonizeDirectedEdge(nStart, nEnd, linePts[1], true)
            let de1 = PolygonizeDirectedEdge(nEnd, nStart, linePts[linePts.count - 2], false)
            let edge = PolygonizeEdge(line)
            edge.setDirectedEdges(de0, de1)
            add(edge)
        }

        private func getNode(_ pt: Coordinate) -> Planargraph.Node {
            if let node = findNode(pt) { return node }
            let node = Planargraph.Node(pt)
            add(node)
            return node
        }

        private func computeNextCWEdges() {
            for node in getNodes() { PolygonizeGraph.computeNextCWEdges(node) }
        }

        /// Turns each maximal ring into minimal rings, linking the edges
        /// counter-clockwise at its intersection nodes.
        private func convertMaximalToMinimalEdgeRings(_ ringEdges: [PolygonizeDirectedEdge]) throws {
            for de in ringEdges {
                let label = de.label
                for node in try PolygonizeGraph.findIntersectionNodes(de, label) {
                    try PolygonizeGraph.computeNextCCWEdges(node, label)
                }
            }
        }

        private static func findIntersectionNodes(_ startDE: PolygonizeDirectedEdge, _ label: Int) throws -> [Planargraph.Node] {
            var de = startDE
            var intNodes: [Planargraph.Node] = []
            repeat {
                let node = de.getFromNode()
                if getDegree(node, label) > 1 { intNodes.append(node) }
                guard let n = de.next else { throw AssertionFailedException("found null DE in ring") }
                de = n
            } while de !== startDE
            return intNodes
        }

        /// The minimal edge rings of the graph.
        func getEdgeRings() throws -> [EdgeRing] {
            computeNextCWEdges()
            PolygonizeGraph.label(dirEdges, -1)
            let maximalRings = try PolygonizeGraph.findLabeledEdgeRings(dirEdges)
            try convertMaximalToMinimalEdgeRings(maximalRings)
            var edgeRingList: [EdgeRing] = []
            for d in dirEdges {
                let de = PolygonizeGraph.pde(d)
                if de.isMarked { continue }
                if de.isInRing { continue }
                edgeRingList.append(try findEdgeRing(de))
            }
            return edgeRingList
        }

        private static func findLabeledEdgeRings(_ dirEdges: [Planargraph.DirectedEdge]) throws -> [PolygonizeDirectedEdge] {
            var edgeRingStarts: [PolygonizeDirectedEdge] = []
            var currLabel = 1
            for d in dirEdges {
                let de = pde(d)
                if de.isMarked { continue }
                if de.label >= 0 { continue }
                edgeRingStarts.append(de)
                let edges = try EdgeRing.findDirEdgesInRing(de)
                for e in edges { e.label = currLabel }
                currLabel += 1
            }
            return edgeRingStarts
        }

        /// Deletes the edges both of whose sides are the same ring, and
        /// returns their lines.
        func deleteCutEdges() throws -> [LineString] {
            computeNextCWEdges()
            _ = try PolygonizeGraph.findLabeledEdgeRings(dirEdges)
            var cutLines: [LineString] = []
            for d in dirEdges {
                let de = PolygonizeGraph.pde(d)
                if de.isMarked { continue }
                let sym = de.pSym
                if de.label == sym.label {
                    de.isMarked = true
                    sym.isMarked = true
                    cutLines.append(de.line)
                }
            }
            return cutLines
        }

        private static func label(_ dirEdges: [Planargraph.DirectedEdge], _ label: Int) {
            for de in dirEdges { pde(de).label = label }
        }

        private static func computeNextCWEdges(_ node: Planargraph.Node) {
            var startDE: PolygonizeDirectedEdge?
            var prevDE: PolygonizeDirectedEdge?
            for d in node.getOutEdges().getEdges() {
                let outDE = pde(d)
                if outDE.isMarked { continue }
                if startDE == nil { startDE = outDE }
                if let prevDE { prevDE.pSym.next = outDE }
                prevDE = outDE
            }
            if let prevDE { prevDE.pSym.next = startDE }
        }

        private static func computeNextCCWEdges(_ node: Planargraph.Node, _ label: Int) throws {
            var firstOutDE: PolygonizeDirectedEdge?
            var prevInDE: PolygonizeDirectedEdge?
            let edges = node.getOutEdges().getEdges()
            for i in stride(from: edges.count - 1, through: 0, by: -1) {
                let de = pde(edges[i])
                let sym = de.pSym
                let outDE: PolygonizeDirectedEdge? = de.label == label ? de : nil
                let inDE: PolygonizeDirectedEdge? = sym.label == label ? sym : nil
                if outDE == nil && inDE == nil { continue } // this edge is not in edgering
                if let inDE { prevInDE = inDE }
                if let outDE {
                    if let p = prevInDE {
                        p.next = outDE
                        prevInDE = nil
                    }
                    if firstOutDE == nil { firstOutDE = outDE }
                }
            }
            if let prevInDE {
                guard let firstOutDE else { throw AssertionFailedException() }
                prevInDE.next = firstOutDE
            }
        }

        private func findEdgeRing(_ startDE: PolygonizeDirectedEdge) throws -> EdgeRing {
            let er = EdgeRing(factory)
            edgeRings.append(er)
            try er.build(startDE)
            return er
        }

        /// Deletes the dangling edges (with an end of degree 1), repeatedly,
        /// and returns their lines, each once (GEOS; JTS may list one twice).
        func deleteDangles() -> [LineString] {
            var nodeStack = findNodesOfDegree(1)
            var dangleLines: [LineString] = []
            var unique = Set<ObjectIdentifier>()
            while let node = nodeStack.popLast() {
                PolygonizeGraph.deleteAllEdges(node)
                for de in node.getOutEdges().getEdges() {
                    de.isMarked = true
                    de.sym?.isMarked = true
                    let ls = PolygonizeGraph.pde(de).line
                    if unique.insert(ObjectIdentifier(ls)).inserted { dangleLines.append(ls) }
                    let toNode = de.getToNode()
                    if PolygonizeGraph.getDegreeNonDeleted(toNode) == 1 { nodeStack.append(toNode) }
                }
            }
            return dangleLines
        }
    }
}
