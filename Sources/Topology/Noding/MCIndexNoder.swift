/// Nodes segment strings by their monotone chains, found overlapping through
/// a spatial index: JTS's `MCIndexNoder`. The index is the STR tree (JTS 1.20
/// uses a Hilbert R-tree here), and the pairs of chains are taken in the
/// order GEOS 3.13 takes them: every chain against the chains after it in
/// the tree's packed order (`STRtree.queryPairs`), the earlier one first.
/// JTS takes each chain in insertion order against the chains of a higher
/// id. The pairs are the same; their order decides which of two equal
/// coordinates (`0.0` and `-0.0`) a node gets, and GEOS's order gives GEOS's.
public final class MCIndexNoder: Noder {
    public private(set) var monoChains: [MonotoneChain] = []
    let index = STRtree<MonotoneChain>()
    var idCounter = 0
    var nodedSegStrings: [SegmentString] = []
    public private(set) var nOverlaps = 0
    let overlapTolerance: Double
    public var segInt: SegmentIntersector?

    public init(_ segInt: SegmentIntersector? = nil, overlapTolerance: Double = 0) {
        self.segInt = segInt
        self.overlapTolerance = overlapTolerance
    }

    public func getNodedSubstrings() -> [SegmentString] { NodedSegmentString.getNodedSubstrings(nodedSegStrings) }

    public func computeNodes(_ inputSegStrings: [SegmentString]) {
        nodedSegStrings = inputSegStrings
        for s in inputSegStrings { add(s) }
        for mc in monoChains { index.insert(mc.getEnvelope(overlapTolerance), mc) }
        intersectChains()
    }

    func intersectChains() {
        guard let segInt else { return }
        index.queryPairs { queryChain, testChain in
            queryChain.computeOverlaps(testChain, overlapTolerance) { mc1, start1, mc2, start2 in
                segInt.processIntersections(mc1.context!, start1, mc2.context!, start2)
            }
            nOverlaps += 1
            return !segInt.isDone()
        }
    }

    func add(_ segStr: SegmentString) {
        for mc in MonotoneChainBuilder.getChains(segStr.getCoordinates(), segStr) {
            mc.id = idCounter
            idCounter += 1
            monoChains.append(mc)
        }
    }
}
