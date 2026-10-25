/// Adds nodes at the interior intersections only, and lists them: JTS's
/// `InteriorIntersectionFinderAdder`.
public final class InteriorIntersectionFinderAdder: SegmentIntersector {
    @exclusivity(unchecked) public var li: RobustLineIntersector
    @exclusivity(unchecked) public private(set) var interiorIntersections: [Coordinate] = []

    public init(_ li: RobustLineIntersector) { self.li = li }

    override public func processIntersections(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int) {
        if e0 === e1 && segIndex0 == segIndex1 { return }
        li.computeIntersection(e0.getCoordinate(segIndex0), e0.getCoordinate(segIndex0 + 1),
                               e1.getCoordinate(segIndex1), e1.getCoordinate(segIndex1 + 1))
        if li.hasIntersection() && li.isInteriorIntersection() {
            for i in 0..<li.getIntersectionNum() { interiorIntersections.append(li.getIntersection(i)) }
            (e0 as! NodedSegmentString).addIntersections(li, segIndex0, 0)
            (e1 as! NodedSegmentString).addIntersections(li, segIndex1, 1)
        }
    }

    override public func isDone() -> Bool { false }
}
