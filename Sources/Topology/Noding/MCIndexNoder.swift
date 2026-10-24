/// Nodes segment strings by their monotone chains, found overlapping through
/// a spatial index: JTS's `MCIndexNoder`. The index is the STR tree (JTS 1.20
/// uses a Hilbert R-tree here: the pairs found are the same, only their order
/// may differ, and the STR tree is GEOS's choice).
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
        intersectChains()
    }

    func intersectChains() {
        guard let segInt else { return }
        for queryChain in monoChains {
            let queryEnv = queryChain.getEnvelope(overlapTolerance)
            for testChain in index.query(queryEnv) {
                if testChain.id > queryChain.id {
                    queryChain.computeOverlaps(testChain, overlapTolerance) { mc1, start1, mc2, start2 in
                        segInt.processIntersections(mc1.context!, start1, mc2.context!, start2)
                    }
                    nOverlaps += 1
                }
                if segInt.isDone() { return }
            }
        }
    }

    func add(_ segStr: SegmentString) {
        for mc in MonotoneChainBuilder.getChains(segStr.getCoordinates(), segStr) {
            mc.id = idCounter
            idCounter += 1
            index.insert(mc.getEnvelope(overlapTolerance), mc)
            monoChains.append(mc)
        }
    }
}
