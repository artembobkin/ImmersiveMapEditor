/// A segment string that records where it is intersected and splits there:
/// JTS's `NodedSegmentString`.
public final class NodedSegmentString: SegmentString, NodableSegmentString {
    /// The nodes, made when first needed (most noded substrings get none).
    @exclusivity(unchecked) private var nodeListStorage: SegmentNodeList?
    public var nodeList: SegmentNodeList {
        if let n = nodeListStorage { return n }
        let n = SegmentNodeList(self)
        nodeListStorage = n
        return n
    }

    override public init(_ pts: [Coordinate], _ data: Any?) {
        super.init(pts, data)
    }

    public convenience init(_ ss: SegmentString) { self.init(ss.getCoordinates(), ss.getData()) }

    /// The noded substrings of every string, in order.
    public static func getNodedSubstrings(_ segStrings: [SegmentString]) -> [SegmentString] {
        var result: [SegmentString] = []
        getNodedSubstrings(segStrings, &result)
        return result
    }

    public static func getNodedSubstrings(_ segStrings: [SegmentString], _ result: inout [SegmentString]) {
        for s in segStrings { (s as! NodedSegmentString).nodeList.addSplitEdges(&result) }
    }

    public func getNodedCoordinates() -> [Coordinate] { nodeList.getSplitCoordinates() }
    public func hasNodes() -> Bool { nodeListStorage.map { $0.size() > 0 } ?? false }

    /// The octant of a segment, 0 for a zero-length one, -1 past the end.
    public func getSegmentOctant(_ index: Int) -> Int {
        if index == pts.count - 1 { return -1 }
        let p0 = pts[index], p1 = pts[index + 1]
        if p0.equals2D(p1) { return 0 }
        return Octant.octant(p0, p1)
    }

    public func addIntersections(_ li: RobustLineIntersector, _ segmentIndex: Int, _ geomIndex: Int) {
        for i in 0..<li.getIntersectionNum() { addIntersection(li, segmentIndex, geomIndex, i) }
    }

    public func addIntersection(_ li: RobustLineIntersector, _ segmentIndex: Int, _ geomIndex: Int, _ intIndex: Int) {
        addIntersection(li.getIntersection(intIndex), segmentIndex)
    }

    public func addIntersection(_ intPt: Coordinate, _ segmentIndex: Int) { _ = addIntersectionNode(intPt, segmentIndex) }

    /// A node at `intPt` on the segment, moved to the next vertex's index
    /// when it is that vertex.
    @discardableResult
    public func addIntersectionNode(_ intPt: Coordinate, _ segmentIndex: Int) -> SegmentNode {
        var normalized = segmentIndex
        let next = normalized + 1
        if next < pts.count && intPt.equals2D(pts[next]) { normalized = next }
        return nodeList.add(intPt, normalized)
    }
}
