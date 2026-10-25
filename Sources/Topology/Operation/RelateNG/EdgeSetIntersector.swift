/// Intersects the edges of both geometries with each other and with
/// themselves, through one index of their monotone chains: JTS's
/// `EdgeSetIntersector`. JTS indexes in a Hilbert R-tree and queries chain
/// by chain; GEOS takes the pairs of its STR tree (`STRtree.queryPairs`),
/// as here.
final class EdgeSetIntersector {
    private let index = STRtree<MonotoneChain>()
    private let envelope: Envelope?
    @exclusivity(unchecked) private var idCounter = 0

    init(_ edgesA: [RelateSegmentString], _ edgesB: [RelateSegmentString], _ env: Envelope?) {
        envelope = env
        addEdges(edgesA)
        addEdges(edgesB)
        index.build()
    }

    private func addEdges(_ segStrings: [RelateSegmentString]) {
        for ss in segStrings {
            for mc in MonotoneChainBuilder.getChains(ss.getCoordinates(), ss)
            where envelope == nil || envelope!.intersects(mc.getEnvelope()) {
                mc.id = idCounter
                idCounter += 1
                index.insert(mc.getEnvelope(), mc)
            }
        }
    }

    func process(_ intersector: EdgeSegmentIntersector) {
        index.queryPairs { queryChain, testChain in
            testChain.computeOverlaps(queryChain) { mc1, start1, mc2, start2 in
                intersector.processIntersections(mc1.context!, start1, mc2.context!, start2)
            }
            return !intersector.isDone()
        }
    }
}
