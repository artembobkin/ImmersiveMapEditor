/// Adds the intersections of segments of the two geometries to the
/// topology computer as pairs of node sections: JTS's
/// `EdgeSegmentIntersector`.
final class EdgeSegmentIntersector: SegmentIntersector {
    @exclusivity(unchecked) private var li = RobustLineIntersector()
    private let topoComputer: TopologyComputer

    init(_ topoBuilder: TopologyComputer) { topoComputer = topoBuilder }

    override func isDone() -> Bool { topoComputer.isResultKnown() }

    override func processIntersections(_ ss0: SegmentString, _ segIndex0: Int, _ ss1: SegmentString, _ segIndex1: Int) {
        if ss0 === ss1 && segIndex0 == segIndex1 { return }
        let rss0 = ss0 as! RelateSegmentString, rss1 = ss1 as! RelateSegmentString
        if rss0.isA {
            addIntersections(rss0, segIndex0, rss1, segIndex1)
        } else {
            addIntersections(rss1, segIndex1, rss0, segIndex0)
        }
    }

    private func addIntersections(_ ssA: RelateSegmentString, _ segIndexA: Int, _ ssB: RelateSegmentString, _ segIndexB: Int) {
        li.computeIntersection(ssA.pts[segIndexA], ssA.pts[segIndexA + 1], ssB.pts[segIndexB], ssB.pts[segIndexB + 1])
        if !li.hasIntersection() { return }
        for i in 0..<li.getIntersectionNum() {
            let intPt = li.getIntersection(i)
            // A node at the end of a segment is added by the next segment only.
            if li.isProper() || (ssA.isContainingSegment(segIndexA, intPt) && ssB.isContainingSegment(segIndexB, intPt)) {
                topoComputer.addIntersection(ssA.createNodeSection(segIndexA, intPt), ssB.createNodeSection(segIndexB, intPt))
            }
        }
    }
}
