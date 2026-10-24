/// Finds whether a set of segment strings intersects a fixed one, indexed
/// once: JTS's `FastSegmentSetIntersectionFinder`.
public final class FastSegmentSetIntersectionFinder {
    private let segSetMutInt: MCIndexSegmentSetMutualIntersector

    public init(_ baseSegStrings: [SegmentString]) { segSetMutInt = MCIndexSegmentSetMutualIntersector(baseSegStrings) }

    public func intersects(_ segStrings: [SegmentString]) -> Bool { intersects(segStrings, SegmentIntersectionDetector()) }

    public func intersects(_ segStrings: [SegmentString], _ intDetector: SegmentIntersectionDetector) -> Bool {
        segSetMutInt.process(segStrings, intDetector)
        return intDetector.hasIntersection
    }
}
