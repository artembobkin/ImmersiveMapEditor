/// A segment string with no nodes: JTS's `BasicSegmentString`.
public final class BasicSegmentString: SegmentString {
    let pts: [Coordinate]
    var data: Any?

    public init(_ pts: [Coordinate], _ data: Any?) {
        self.pts = pts
        self.data = data
    }

    public func getData() -> Any? { data }
    public func setData(_ data: Any?) { self.data = data }
    public func size() -> Int { pts.count }
    public func getCoordinate(_ i: Int) -> Coordinate { pts[i] }
    public func getCoordinates() -> [Coordinate] { pts }
    public func isClosed() -> Bool { pts[0] == pts[pts.count - 1] }
}
