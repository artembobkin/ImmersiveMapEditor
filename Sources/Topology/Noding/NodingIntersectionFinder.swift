/// Finds intersections that show segment strings are not fully noded (an
/// interior intersection, or a vertex of one on the interior of another):
/// JTS's `NodingIntersectionFinder`.
public final class NodingIntersectionFinder: SegmentIntersector {
    @exclusivity(unchecked) public var findAllIntersections = false
    @exclusivity(unchecked) public var isCheckEndSegmentsOnly = false
    @exclusivity(unchecked) public var keepIntersections = true
    @exclusivity(unchecked) public var isInteriorIntersectionsOnly = false
    @exclusivity(unchecked) var li: RobustLineIntersector
    @exclusivity(unchecked) public private(set) var interiorIntersection: Coordinate?
    @exclusivity(unchecked) public private(set) var intSegments: [Coordinate]?
    @exclusivity(unchecked) public private(set) var intersections: [Coordinate] = []
    @exclusivity(unchecked) public private(set) var intersectionCount = 0

    public init(_ li: RobustLineIntersector) { self.li = li }

    public static func createAnyIntersectionFinder(_ li: RobustLineIntersector) -> NodingIntersectionFinder {
        NodingIntersectionFinder(li)
    }

    public static func createAllIntersectionsFinder(_ li: RobustLineIntersector) -> NodingIntersectionFinder {
        let f = NodingIntersectionFinder(li)
        f.findAllIntersections = true
        return f
    }

    public static func createInteriorIntersectionsFinder(_ li: RobustLineIntersector) -> NodingIntersectionFinder {
        let f = NodingIntersectionFinder(li)
        f.findAllIntersections = true
        f.isInteriorIntersectionsOnly = true
        return f
    }

    public static func createIntersectionCounter(_ li: RobustLineIntersector) -> NodingIntersectionFinder {
        let f = NodingIntersectionFinder(li)
        f.findAllIntersections = true
        f.keepIntersections = false
        return f
    }

    public static func createInteriorIntersectionCounter(_ li: RobustLineIntersector) -> NodingIntersectionFinder {
        let f = NodingIntersectionFinder(li)
        f.isInteriorIntersectionsOnly = true
        f.findAllIntersections = true
        f.keepIntersections = false
        return f
    }

    public func count() -> Int { intersectionCount }
    public func hasIntersection() -> Bool { interiorIntersection != nil }

    override public func processIntersections(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int) {
        if !findAllIntersections && hasIntersection() { return }
        let isSameSegString = e0 === e1
        if isSameSegString && segIndex0 == segIndex1 { return }
        if isCheckEndSegmentsOnly {
            let endPresent = NodingIntersectionFinder.isEndSegment(e0, segIndex0) || NodingIntersectionFinder.isEndSegment(e1, segIndex1)
            if !endPresent { return }
        }
        let p00 = e0.getCoordinate(segIndex0), p01 = e0.getCoordinate(segIndex0 + 1)
        let p10 = e1.getCoordinate(segIndex1), p11 = e1.getCoordinate(segIndex1 + 1)
        let isEnd00 = segIndex0 == 0, isEnd01 = segIndex0 + 2 == e0.size()
        let isEnd10 = segIndex1 == 0, isEnd11 = segIndex1 + 2 == e1.size()
        li.computeIntersection(p00, p01, p10, p11)
        let isInteriorInt = li.hasIntersection() && li.isInteriorIntersection()
        var isInteriorVertexInt = false
        if !isInteriorIntersectionsOnly {
            let isAdjacentSegment = isSameSegString && abs(segIndex1 - segIndex0) <= 1
            isInteriorVertexInt = !isAdjacentSegment
                && NodingIntersectionFinder.isInteriorVertexIntersection(p00, p01, p10, p11, isEnd00, isEnd01, isEnd10, isEnd11)
        }
        if isInteriorInt || isInteriorVertexInt {
            intSegments = [p00, p01, p10, p11]
            interiorIntersection = li.getIntersection(0)
            if keepIntersections { intersections.append(interiorIntersection!) }
            intersectionCount += 1
        }
    }

    static func isInteriorVertexIntersection(_ p00: Coordinate, _ p01: Coordinate, _ p10: Coordinate, _ p11: Coordinate,
                                             _ isEnd00: Bool, _ isEnd01: Bool, _ isEnd10: Bool, _ isEnd11: Bool) -> Bool {
        if isInteriorVertexIntersection(p00, p10, isEnd00, isEnd10) { return true }
        if isInteriorVertexIntersection(p00, p11, isEnd00, isEnd11) { return true }
        if isInteriorVertexIntersection(p01, p10, isEnd01, isEnd10) { return true }
        if isInteriorVertexIntersection(p01, p11, isEnd01, isEnd11) { return true }
        return false
    }

    static func isInteriorVertexIntersection(_ p0: Coordinate, _ p1: Coordinate, _ isEnd0: Bool, _ isEnd1: Bool) -> Bool {
        if isEnd0 && isEnd1 { return false }
        return p0.equals2D(p1)
    }

    static func isEndSegment(_ s: SegmentString, _ index: Int) -> Bool { index == 0 || index >= s.size() - 2 }

    override public func isDone() -> Bool {
        if findAllIntersections { return false }
        return interiorIntersection != nil
    }
}
