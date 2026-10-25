/// A growing list of coordinates that can refuse a point repeating the last
/// one: JTS's `CoordinateList`, a value.
public struct CoordinateList {
    public private(set) var points: [Coordinate] = []

    public init() {}

    public init(_ points: [Coordinate]) { self.points = points }

    public var count: Int { points.count }
    public var isEmpty: Bool { points.isEmpty }
    public subscript(i: Int) -> Coordinate { points[i] }

    /// Adds `p`, unless repeats are refused and it equals the last point.
    public mutating func add(_ p: Coordinate, _ allowRepeated: Bool = true) {
        if !allowRepeated, let last = points.last, last.equals2D(p) { return }
        points.append(p)
    }

    /// Adds the points in order, or reversed, under the same rule.
    public mutating func add(_ pts: [Coordinate], _ allowRepeated: Bool, _ direction: Bool = true) {
        if direction {
            for p in pts { add(p, allowRepeated) }
        } else {
            for p in pts.reversed() { add(p, allowRepeated) }
        }
    }

    /// Closes the list as a ring: its first point again, if the last differs.
    public mutating func closeRing() {
        if let first = points.first, let last = points.last, !first.equals2D(last) { points.append(first) }
    }

    /// The points, reversed when `isForward` is false.
    public func toCoordinateArray(_ isForward: Bool = true) -> [Coordinate] {
        isForward ? points : points.reversed()
    }
}
