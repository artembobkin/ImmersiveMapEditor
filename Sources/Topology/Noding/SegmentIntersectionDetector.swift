/// Finds whether segments intersect, and of which kinds (proper or not),
/// stopping as soon as what is asked is found: JTS's `SegmentIntersectionDetector`.
public final class SegmentIntersectionDetector: SegmentIntersector {
    @exclusivity(unchecked) private var li = RobustLineIntersector()
    public var findProper = false
    public var findAllIntersectionTypes = false
    public private(set) var hasIntersection = false
    public private(set) var hasProperIntersection = false
    public private(set) var hasNonProperIntersection = false
    public private(set) var intersection: Coordinate?

    public init() {}

    public func processIntersections(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int) {
        if e0 === e1 && segIndex0 == segIndex1 { return }
        li.computeIntersection(e0.getCoordinate(segIndex0), e0.getCoordinate(segIndex0 + 1),
                               e1.getCoordinate(segIndex1), e1.getCoordinate(segIndex1 + 1))
        if li.hasIntersection() {
            hasIntersection = true
            let isProper = li.isProper()
            if isProper { hasProperIntersection = true } else { hasNonProperIntersection = true }
            if intersection == nil || !(findProper && !isProper) { intersection = li.getIntersection(0) }
        }
    }

    public func isDone() -> Bool {
        if findAllIntersectionTypes { return hasProperIntersection && hasNonProperIntersection }
        if findProper { return hasProperIntersection }
        return hasIntersection
    }
}
