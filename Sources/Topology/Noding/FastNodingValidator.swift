/// Checks that segment strings are fully noded, with a monotone chain index:
/// JTS's `FastNodingValidator`.
public final class FastNodingValidator {
    let segStrings: [SegmentString]
    @exclusivity(unchecked) public var findAllIntersections = false
    @exclusivity(unchecked) var segInt: NodingIntersectionFinder?
    @exclusivity(unchecked) var valid = true

    public init(_ segStrings: [SegmentString]) { self.segStrings = segStrings }

    public static func computeIntersections(_ segStrings: [SegmentString]) -> [Coordinate] {
        let nv = FastNodingValidator(segStrings)
        nv.findAllIntersections = true
        _ = nv.isValid()
        return nv.getIntersections()
    }

    public func getIntersections() -> [Coordinate] { segInt?.intersections ?? [] }

    public func isValid() -> Bool {
        execute()
        return valid
    }

    public func getErrorMessage() -> String {
        if valid { return "no intersections found" }
        let s = segInt!.intSegments!
        return "found non-noded intersection between LINESTRING ( \(s[0].x) \(s[0].y), \(s[1].x) \(s[1].y) ) and LINESTRING ( \(s[2].x) \(s[2].y), \(s[3].x) \(s[3].y) )"
    }

    public func checkValid() throws {
        execute()
        if !valid { throw TopologyException(getErrorMessage(), segInt!.interiorIntersection) }
    }

    func execute() {
        if segInt != nil { return }
        valid = true
        let finder = NodingIntersectionFinder(RobustLineIntersector())
        finder.findAllIntersections = findAllIntersections
        segInt = finder
        let noder = MCIndexNoder(finder)
        noder.computeNodes(segStrings)
        if finder.hasIntersection() { valid = false }
    }
}
