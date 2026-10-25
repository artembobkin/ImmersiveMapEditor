/// Locates points in an areal geometry by counting the crossings of a ray,
/// with the segments of its rings in an interval index on y, built at the
/// first query: JTS's `IndexedPointInAreaLocator`. Only closed lines count,
/// so an empty or lineal geometry has every point outside.
///
/// The index is GEOS 3.13's: a one-dimensional STR tree of capacity 10
/// (`IntervalSTRtree`), each segment's interval its ends' y by `std::minmax`
/// (JTS: a `SortedPackedIntervalRTree`, by `Math.min` and `Math.max`). For
/// finite coordinates a query meets the same segments either way, and the
/// count depends only on which; a NaN y makes them differ, as in GEOS.
public final class IndexedPointInAreaLocator: PointOnGeometryLocator {
    @exclusivity(unchecked) private var geom: Geometry?
    @exclusivity(unchecked) private var index: IntervalSTRtree<LineSegment>?
    @exclusivity(unchecked) private var isEmpty = false

    public init(_ g: Geometry) { geom = g }

    public func locate(_ p: Coordinate) -> Int {
        if index == nil { createIndex() }
        var rcc = RayCrossingCounter(p)
        if !isEmpty {
            index!.query(p.y, p.y) { seg in rcc.countSegment(seg.p0, seg.p1) }
        }
        return rcc.location
    }

    private func createIndex() {
        let tree = IntervalSTRtree<LineSegment>(nodeCapacity: 10)
        let g = geom!
        isEmpty = g.isEmpty()
        if !isEmpty {
            let lines = LinearComponentExtracter.getLines(g)
            tree.reserveCapacity(lines.reduce(0) { $0 + $1.points.count })
            for line in lines where line.isClosed() {
                let pts = line.points
                for i in stride(from: 1, to: pts.count, by: 1) {
                    let seg = LineSegment(pts[i - 1], pts[i])
                    // std::minmax: the second first only when it is less.
                    if seg.p1.y < seg.p0.y {
                        tree.insert(seg.p1.y, seg.p0.y, seg)
                    } else {
                        tree.insert(seg.p0.y, seg.p1.y, seg)
                    }
                }
            }
        }
        index = tree
        geom = nil
    }
}
