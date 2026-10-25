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
    /// set whose envelopes meet, to `segInt`. Once it is done, as GEOS 3.13
    /// runs it: the query of the current chain stops, and every later chain
    /// still meets the first test chain its query finds (JTS stops at once).
    /// This changes no answer, only what is computed after it: an
    /// intersection point taken later, an orientation test that meets a
    /// non-finite point.
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
                queryChain.computeOverlaps(testChain, overlapTolerance, segInt)
                if segInt.isDone() { break }
            }
        }
    }
}
