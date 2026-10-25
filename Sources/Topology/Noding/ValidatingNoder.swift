/// A noder whose result is checked to be fully noded: JTS's `ValidatingNoder`.
public final class ValidatingNoder: Noder {
    let noder: Noder
    @exclusivity(unchecked) var nodedSS: [SegmentString] = []

    public init(_ noder: Noder) { self.noder = noder }

    public func computeNodes(_ segStrings: [SegmentString]) throws {
        try noder.computeNodes(segStrings)
        nodedSS = noder.getNodedSubstrings()
        try FastNodingValidator(nodedSS).checkValid()
    }

    public func getNodedSubstrings() -> [SegmentString] { nodedSS }
}
