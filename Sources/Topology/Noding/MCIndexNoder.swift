/// Nodes segment strings by their monotone chains, found overlapping through
/// a spatial index: JTS's `MCIndexNoder`. The index is the STR tree (JTS 1.20
/// uses a Hilbert R-tree here), and the pairs of chains are taken in the
/// order GEOS 3.13 takes them: every chain against the chains after it in
/// the tree's packed order (`STRtree.queryPairs`), the earlier one first.
/// JTS takes each chain in insertion order against the chains of a higher
/// id. The pairs are the same; their order decides which of two equal
/// coordinates (`0.0` and `-0.0`) a node gets, and GEOS's order gives GEOS's.
public final class MCIndexNoder: Noder {
    @exclusivity(unchecked) public private(set) var monoChains: [MonotoneChain] = []
    /// The chains by envelope, held unmanaged (`monoChains` keeps them
    /// alive), so reading them back costs no reference counting.
    let index = STRtree<Unmanaged<MonotoneChain>>()
    @exclusivity(unchecked) var idCounter = 0
    @exclusivity(unchecked) var nodedSegStrings: [SegmentString] = []
    @exclusivity(unchecked) public private(set) var nOverlaps = 0
    let overlapTolerance: Double
    @exclusivity(unchecked) public var segInt: SegmentIntersector?

    public init(_ segInt: SegmentIntersector? = nil, overlapTolerance: Double = 0) {
        self.segInt = segInt
        self.overlapTolerance = overlapTolerance
    }

    public func getNodedSubstrings() -> [SegmentString] { NodedSegmentString.getNodedSubstrings(nodedSegStrings) }

    public func computeNodes(_ inputSegStrings: [SegmentString]) {
        nodedSegStrings = inputSegStrings
        monoChains.reserveCapacity(monoChains.count + 2 * inputSegStrings.count)
        for s in inputSegStrings { add(s) }
        for mc in monoChains { index.insert(mc.getEnvelope(overlapTolerance), Unmanaged.passUnretained(mc)) }
        intersectChains()
    }

    func intersectChains() {
        guard let segInt else { return }
        let tolerance = overlapTolerance
        var overlaps = 0
        index.queryPairs { query, test in
            query._withUnsafeGuaranteedRef { queryChain in
                test._withUnsafeGuaranteedRef { testChain in
                    queryChain.computeOverlaps(testChain, tolerance, segInt)
                }
            }
            overlaps += 1
            return !segInt.isDone()
        }
        nOverlaps += overlaps
    }

    func add(_ segStr: SegmentString) {
        let first = monoChains.count
        MonotoneChainBuilder.appendChains(segStr.getCoordinates(), segStr, &monoChains)
        for k in first..<monoChains.count {
            monoChains[k].id = idCounter
            idCounter += 1
        }
    }
}
