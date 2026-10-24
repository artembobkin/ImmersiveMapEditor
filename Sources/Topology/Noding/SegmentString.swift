/// A sequence of segments with data attached: JTS's `SegmentString`, a
/// class protocol (the noders keep segment strings by identity).
public protocol SegmentString: AnyObject {
    func getData() -> Any?
    func setData(_ data: Any?)
    func size() -> Int
    func getCoordinate(_ i: Int) -> Coordinate
    func getCoordinates() -> [Coordinate]
    func isClosed() -> Bool
}

extension SegmentString {
    /// The vertex before `index` in a closed string.
    public func prevInRing(_ index: Int) -> Coordinate {
        var prev = index - 1
        if prev < 0 { prev = size() - 2 }
        return getCoordinate(prev)
    }

    /// The vertex after `index` in a closed string.
    public func nextInRing(_ index: Int) -> Coordinate {
        var next = index + 1
        if next > size() - 1 { next = 1 }
        return getCoordinate(next)
    }
}
