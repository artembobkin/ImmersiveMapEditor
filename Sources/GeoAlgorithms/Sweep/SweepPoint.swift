/// geo's `SweepPoint`: a coordinate ordered lexicographically by `x`, then `y`. Its `PartialOrd`
/// and the panicking `Ord` (`partial_cmp(...).unwrap()`) are kept apart, because the sweep uses
/// both and only the latter fails on NaN.

struct SweepPoint: Hashable, CustomStringConvertible {
    let coord: GeoCoord

    init(_ coord: GeoCoord) {
        self.coord = coord
    }

    init(x: Double, y: Double) {
        self.coord = GeoCoord(x: x, y: y)
    }

    var x: Double { coord.x }
    var y: Double { coord.y }

    var description: String { "SPt(\(coord.x), \(coord.y))" }

    /// `PartialOrd::partial_cmp`: by `x`, then by `y`, `nil` if a NaN is involved.
    func partialCmp(_ other: SweepPoint) -> RustOrdering? {
        switch rustPartialCmp(coord.x, other.coord.x) {
        case .equal?: return rustPartialCmp(coord.y, other.coord.y)
        case let o: return o
        }
    }

    /// `Ord::cmp`, which unwraps `partial_cmp` and so panics on NaN.
    func cmp(_ other: SweepPoint) throws(GeoPanic) -> RustOrdering {
        guard let o = partialCmp(other) else { throw GeoPanic.unwrapNone }
        return o
    }

    // The `PartialOrd` operators: `false` whenever `partial_cmp` is `None`.
    func lt(_ other: SweepPoint) -> Bool { partialCmp(other) == .less }
    func gt(_ other: SweepPoint) -> Bool { partialCmp(other) == .greater }
    func le(_ other: SweepPoint) -> Bool {
        let o = partialCmp(other)
        return o == .less || o == .equal
    }
    func ge(_ other: SweepPoint) -> Bool {
        let o = partialCmp(other)
        return o == .greater || o == .equal
    }
}
