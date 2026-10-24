/// Intersects a set of segment strings with a fixed base set, indexed once
/// by their monotone chains in an STR tree: JTS's
/// `MCIndexSegmentSetMutualIntersector`. Base chains outside the envelope
/// (when given) are not indexed, and nor are the test chains outside it.
public final class MCIndexSegmentSetMutualIntersector {
    private let index = STRtree<MonotoneChain>()
    private let overlapTolerance: Double
    private let envelope: Envelope?

    public init(_ baseSegStrings: [SegmentString], _ env: Envelope? = nil, overlapTolerance: Double = 0) {
        envelope = env
        self.overlapTolerance = overlapTolerance
        for ss in baseSegStrings where ss.size() > 0 {
            for mc in MonotoneChainBuilder.getChains(ss.getCoordinates(), ss)
            where envelope == nil || envelope!.intersects(mc.getEnvelope()) {
                index.insert(mc.getEnvelope(overlapTolerance), mc)
            }
        }
        index.build()
    }

    /// Every pair of a segment of `segStrings` with a segment of the base
    /// set whose envelopes meet, to `segInt`, until it is done.
    public func process(_ segStrings: [SegmentString], _ segInt: SegmentIntersector) {
        var monoChains: [MonotoneChain] = []
        for ss in segStrings where ss.size() > 0 {
            for mc in MonotoneChainBuilder.getChains(ss.getCoordinates(), ss)
            where envelope == nil || envelope!.intersects(mc.getEnvelope()) {
                monoChains.append(mc)
            }
        }
        for queryChain in monoChains {
            let queryEnv = queryChain.getEnvelope(overlapTolerance)
            for testChain in index.query(queryEnv) {
                queryChain.computeOverlaps(testChain, overlapTolerance) { mc1, start1, mc2, start2 in
                    segInt.processIntersections(mc1.context!, start1, mc2.context!, start2)
                }
                if segInt.isDone() { return }
            }
        }
    }
}
