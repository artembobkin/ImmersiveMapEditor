/// Adds a node to both segment strings at every intersection of their
/// segments that is not a trivial one (adjacent segments of one string):
/// JTS's `IntersectionAdder`.
public final class IntersectionAdder: SegmentIntersector {
    public static func isAdjacentSegments(_ i1: Int, _ i2: Int) -> Bool { abs(i1 - i2) == 1 }

    @exclusivity(unchecked) public private(set) var hasIntersection = false
    @exclusivity(unchecked) public private(set) var hasProper = false
    @exclusivity(unchecked) public private(set) var hasProperInterior = false
    @exclusivity(unchecked) public private(set) var hasInterior = false
    @exclusivity(unchecked) public private(set) var properIntersectionPoint: Coordinate?
    @exclusivity(unchecked) public var li: RobustLineIntersector
    @exclusivity(unchecked) public var numIntersections = 0
    @exclusivity(unchecked) public var numInteriorIntersections = 0
    @exclusivity(unchecked) public var numProperIntersections = 0
    @exclusivity(unchecked) public var numTests = 0

    public init(_ li: RobustLineIntersector) { self.li = li }

    func isTrivialIntersection(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int) -> Bool {
        if e0 === e1 && li.getIntersectionNum() == 1 {
            if IntersectionAdder.isAdjacentSegments(segIndex0, segIndex1) { return true }
            if e0.isClosed() {
                let maxSegIndex = e0.size() - 1
                if (segIndex0 == 0 && segIndex1 == maxSegIndex) || (segIndex1 == 0 && segIndex0 == maxSegIndex) { return true }
            }
        }
        return false
    }

    override public func processIntersections(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int) {
        if e0 === e1 && segIndex0 == segIndex1 { return }
        numTests += 1
        li.computeIntersection(e0.getCoordinate(segIndex0), e0.getCoordinate(segIndex0 + 1),
                               e1.getCoordinate(segIndex1), e1.getCoordinate(segIndex1 + 1))
        if li.hasIntersection() {
            numIntersections += 1
            if li.isInteriorIntersection() {
                numInteriorIntersections += 1
                hasInterior = true
            }
            if !isTrivialIntersection(e0, segIndex0, e1, segIndex1) {
                hasIntersection = true
                (e0 as! NodedSegmentString).addIntersections(li, segIndex0, 0)
                (e1 as! NodedSegmentString).addIntersections(li, segIndex1, 1)
                if li.isProper() {
                    numProperIntersections += 1
                    hasProper = true
                    hasProperInterior = true
                }
            }
        }
    }

    override public func isDone() -> Bool { false }
}
