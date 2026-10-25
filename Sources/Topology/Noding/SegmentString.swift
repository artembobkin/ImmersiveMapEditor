/// A sequence of segments with data attached: JTS's `SegmentString`. A base
/// class here (JTS: an interface), holding the points and the data, so the
/// noders call its methods statically and pass it without the reference
/// counting a protocol existential costs; the noders keep segment strings
/// by identity.
public class SegmentString {
    let pts: [Coordinate]
    @exclusivity(unchecked) var data: Any?

    init(_ pts: [Coordinate], _ data: Any?) {
        self.pts = pts
        self.data = data
    }

    public final func getData() -> Any? { data }
    public final func setData(_ data: Any?) { self.data = data }
    public final func size() -> Int { pts.count }
    public final func getCoordinate(_ i: Int) -> Coordinate { pts[i] }
    public final func getCoordinates() -> [Coordinate] { pts }
    public final func isClosed() -> Bool { pts[0] == pts[pts.count - 1] }

    /// The vertex before `index` in a closed string.
    public final func prevInRing(_ index: Int) -> Coordinate {
        var prev = index - 1
        if prev < 0 { prev = size() - 2 }
        return getCoordinate(prev)
    }

    /// The vertex after `index` in a closed string.
    public final func nextInRing(_ index: Int) -> Coordinate {
        var next = index + 1
        if next > size() - 1 { next = 1 }
        return getCoordinate(next)
    }
}
