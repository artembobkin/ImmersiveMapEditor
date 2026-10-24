/// A ring of result area edges linked node to node as they come around each
/// node, which may touch itself; split into minimal rings for the polygons:
/// JTS's `MaximalEdgeRing`.
final class MaximalEdgeRing {
    private static let stateFindIncoming = 1
    private static let stateLinkOutgoing = 2

    /// Links the result edges around a node, each incoming one to the next
    /// outgoing one counter-clockwise.
    static func linkResultAreaMaxRingAtNode(_ nodeEdge: OverlayEdge) throws {
        try Assert.isTrue(nodeEdge.isInResultArea, "Attempt to link non-result edge")
        let endOut = nodeEdge.oNextOE
        var currOut = endOut
        var state = stateFindIncoming
        var currResultIn: OverlayEdge?
        repeat {
            if let r = currResultIn, r.isResultMaxLinked { return }
            switch state {
            case stateFindIncoming:
                let currIn = currOut.symOE
                if currIn.isInResultArea {
                    currResultIn = currIn
                    state = stateLinkOutgoing
                }
            case stateLinkOutgoing:
                if currOut.isInResultArea {
                    currResultIn!.setNextResultMax(currOut)
                    state = stateFindIncoming
                }
            default: break
            }
            currOut = currOut.oNextOE
        } while currOut !== endOut
        if state == stateLinkOutgoing { throw TopologyException("no outgoing edge found", nodeEdge.coordinate) }
    }

    unowned(unsafe) let startEdge: OverlayEdge

    init(_ e: OverlayEdge) throws {
        startEdge = e
        try attachEdges(e)
    }

    private func attachEdges(_ startEdge: OverlayEdge) throws {
        var edge = startEdge
        repeat {
            if edge.maxEdgeRing === self {
                throw TopologyException("Ring edge visited twice at \(edge.coordinate)", edge.coordinate)
            }
            guard let next = edge.nextResultMax else { throw TopologyException("Ring edge missing at", edge.dest) }
            edge.maxEdgeRing = self
            edge = next
        } while edge !== startEdge
    }

    func buildMinimalRings(_ factory: GeometryFactory) throws -> [OverlayEdgeRing] {
        try linkMinimalRings()
        var minEdgeRings: [OverlayEdgeRing] = []
        var e = startEdge
        repeat {
            if e.edgeRing == nil { minEdgeRings.append(try OverlayEdgeRing(e, factory)) }
            e = e.nextResultMax!
        } while e !== startEdge
        return minEdgeRings
    }

    private func linkMinimalRings() throws {
        var e = startEdge
        repeat {
            try MaximalEdgeRing.linkMinRingEdgesAtNode(e, self)
            e = e.nextResultMax!
        } while e !== startEdge
    }

    /// Links the edges of this maximal ring at a node into minimal rings:
    /// each incoming edge to the outgoing one clockwise after it.
    private static func linkMinRingEdgesAtNode(_ nodeEdge: OverlayEdge, _ maxRing: MaximalEdgeRing) throws {
        let endOut = nodeEdge
        var currMaxRingOut: OverlayEdge? = endOut
        var currOut = endOut.oNextOE
        repeat {
            if isAlreadyLinked(currOut.symOE, maxRing) { return }
            if currMaxRingOut == nil {
                currMaxRingOut = selectMaxOutEdge(currOut, maxRing)
            } else {
                currMaxRingOut = linkMaxInEdge(currOut, currMaxRingOut!, maxRing)
            }
            currOut = currOut.oNextOE
        } while currOut !== endOut
        if currMaxRingOut != nil {
            throw TopologyException("Unmatched edge found during min-ring linking", nodeEdge.coordinate)
        }
    }

    private static func isAlreadyLinked(_ edge: OverlayEdge, _ maxRing: MaximalEdgeRing) -> Bool {
        edge.maxEdgeRing === maxRing && edge.isResultLinked
    }

    private static func selectMaxOutEdge(_ currOut: OverlayEdge, _ maxEdgeRing: MaximalEdgeRing) -> OverlayEdge? {
        currOut.maxEdgeRing === maxEdgeRing ? currOut : nil
    }

    private static func linkMaxInEdge(_ currOut: OverlayEdge, _ currMaxRingOut: OverlayEdge,
                                      _ maxEdgeRing: MaximalEdgeRing) -> OverlayEdge? {
        let currIn = currOut.symOE
        if currIn.maxEdgeRing !== maxEdgeRing { return currMaxRingOut }
        currIn.setNextResult(currMaxRingOut)
        return nil
    }
}
