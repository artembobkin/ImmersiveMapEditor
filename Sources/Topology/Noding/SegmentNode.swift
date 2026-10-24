/// An intersection on a segment string: JTS's `SegmentNode`, ordered along
/// the string by segment index, then along the segment.
public struct SegmentNode: CustomStringConvertible {
    public let coord: Coordinate
    public let segmentIndex: Int
    let segmentOctant: Int
    public let isInterior: Bool

    init(_ segString: NodedSegmentString, _ coord: Coordinate, _ segmentIndex: Int, _ segmentOctant: Int) {
        self.coord = coord
        self.segmentIndex = segmentIndex
        self.segmentOctant = segmentOctant
        isInterior = !coord.equals2D(segString.getCoordinate(segmentIndex))
    }

    public func isEndPoint(_ maxSegmentIndex: Int) -> Bool {
        if segmentIndex == 0 && !isInterior { return true }
        if segmentIndex == maxSegmentIndex { return true }
        return false
    }

    public func compareTo(_ other: SegmentNode) -> Int {
        if segmentIndex < other.segmentIndex { return -1 }
        if segmentIndex > other.segmentIndex { return 1 }
        if coord.equals2D(other.coord) { return 0 }
        if !isInterior { return -1 }
        if !other.isInterior { return 1 }
        return SegmentPointComparator.compare(segmentOctant, coord, other.coord)
    }

    public var description: String { "\(segmentIndex):\(coord)" }
}
