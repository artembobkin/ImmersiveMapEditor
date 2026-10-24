/// A segment string that takes intersection nodes: JTS's `NodableSegmentString`.
public protocol NodableSegmentString: SegmentString {
    func addIntersection(_ intPt: Coordinate, _ segmentIndex: Int)
}
