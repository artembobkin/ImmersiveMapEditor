/// Nodes again and again until no new interior intersection appears, with
/// intersections rounded to a precision model: JTS's `IteratedNoder`.
public final class IteratedNoder: Noder {
    public static let maxIter = 5

    let pm: PrecisionModel
    @exclusivity(unchecked) var li = RobustLineIntersector()
    @exclusivity(unchecked) var nodedSegStrings: [SegmentString] = []
    @exclusivity(unchecked) public var maximumIterations = IteratedNoder.maxIter

    public init(_ pm: PrecisionModel) {
        self.pm = pm
        li.precisionModel = pm
    }

    public func getNodedSubstrings() -> [SegmentString] { nodedSegStrings }

    public func computeNodes(_ segStrings: [SegmentString]) throws {
        nodedSegStrings = segStrings
        var iterations = 0
        var lastNodesCreated = -1
        repeat {
            let created = node(nodedSegStrings)
            iterations += 1
            if lastNodesCreated > 0 && created >= lastNodesCreated && iterations > maximumIterations {
                throw TopologyException("Iterated noding failed to converge after \(iterations) iterations")
            }
            lastNodesCreated = created
        } while lastNodesCreated > 0
    }

    func node(_ segStrings: [SegmentString]) -> Int {
        let si = IntersectionAdder(li)
        let noder = MCIndexNoder(si)
        noder.computeNodes(segStrings)
        nodedSegStrings = noder.getNodedSubstrings()
        return si.numInteriorIntersections
    }
}
