/// Builds the polygons of an overlay from its result area edges: maximal
/// rings, split into minimal ones, each shell with its holes, and the holes
/// left free placed in the smallest shell holding them: JTS's
/// `PolygonBuilder` of OverlayNG.
final class PolygonBuilder {
    private let factory: GeometryFactory
    @exclusivity(unchecked) private(set) var shellList: [OverlayEdgeRing] = []
    @exclusivity(unchecked) private var freeHoleList: [OverlayEdgeRing] = []
    private let isEnforcePolygonal: Bool

    init(_ resultAreaEdges: [OverlayEdge], _ factory: GeometryFactory, isEnforcePolygonal: Bool = true) throws {
        self.factory = factory
        self.isEnforcePolygonal = isEnforcePolygonal
        try buildRings(resultAreaEdges)
    }

    func getPolygons() -> [Polygon] { shellList.map { $0.toPolygon(factory) } }

    private func buildRings(_ resultAreaEdges: [OverlayEdge]) throws {
        for edge in resultAreaEdges { try MaximalEdgeRing.linkResultAreaMaxRingAtNode(edge) }
        let maxRings = try PolygonBuilder.buildMaximalRings(resultAreaEdges)
        try buildMinimalRings(maxRings)
        try placeFreeHoles()
    }

    private static func buildMaximalRings(_ edges: [OverlayEdge]) throws -> [MaximalEdgeRing] {
        var edgeRings: [MaximalEdgeRing] = []
        for e in edges where e.isInResultArea && e.label.isBoundaryEither() && e.maxEdgeRing == nil {
            edgeRings.append(try MaximalEdgeRing(e))
        }
        return edgeRings
    }

    private func buildMinimalRings(_ maxRings: [MaximalEdgeRing]) throws {
        for erMax in maxRings {
            let minRings = try erMax.buildMinimalRings(factory)
            try assignShellsAndHoles(minRings)
        }
    }

    private func assignShellsAndHoles(_ minRings: [OverlayEdgeRing]) throws {
        if let shell = try findSingleShell(minRings) {
            for er in minRings where er.isHole { er.setShell(shell) }
            shellList.append(shell)
        } else {
            freeHoleList.append(contentsOf: minRings)
        }
    }

    private func findSingleShell(_ edgeRings: [OverlayEdgeRing]) throws -> OverlayEdgeRing? {
        var shellCount = 0
        var shell: OverlayEdgeRing?
        for er in edgeRings where !er.isHole {
            shell = er
            shellCount += 1
        }
        try Assert.isTrue(shellCount <= 1, "found two shells in EdgeRing list")
        return shell
    }

    private func placeFreeHoles() throws {
        for hole in freeHoleList where hole.getShell() == nil {
            let shell = hole.findEdgeRingContaining(shellList)
            if isEnforcePolygonal && shell == nil {
                throw TopologyException("unable to assign free hole to a shell", hole.coordinate)
            }
            hole.setShell(shell)
        }
    }
}
