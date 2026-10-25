/// A segment string with no nodes: JTS's `BasicSegmentString`.
public final class BasicSegmentString: SegmentString {
    override public init(_ pts: [Coordinate], _ data: Any?) { super.init(pts, data) }
}
