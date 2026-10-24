/// A segment string that records where it is intersected and splits there:
/// JTS's `NodedSegmentString`.
public final class NodedSegmentString: NodableSegmentString {
    public private(set) var nodeList: SegmentNodeList!
    let pts: [Coordinate]
    var data: Any?

    public init(_ pts: [Coordinate], _ data: Any?) {
        self.pts = pts
        self.data = data
        nodeList = SegmentNodeList(self)
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

    public func getData() -> Any? { data }
    public func setData(_ data: Any?) { self.data = data }
    public func size() -> Int { pts.count }
    public func getCoordinate(_ i: Int) -> Coordinate { pts[i] }
    public func getCoordinates() -> [Coordinate] { pts }
    public func getNodedCoordinates() -> [Coordinate] { nodeList.getSplitCoordinates() }
    public func isClosed() -> Bool { pts[0] == pts[pts.count - 1] }
    public func hasNodes() -> Bool { nodeList.size() > 0 }

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
