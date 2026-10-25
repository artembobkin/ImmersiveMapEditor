/// Locates points in an areal geometry by counting the crossings of a ray,
/// with the segments of its rings in an interval index on y, built at the
/// first query: JTS's `IndexedPointInAreaLocator`. Only closed lines count,
/// so an empty or lineal geometry has every point outside.
public final class IndexedPointInAreaLocator: PointOnGeometryLocator {
    private var geom: Geometry?
    private var index: SortedPackedIntervalRTree<LineSegment>?
    private var isEmpty = false

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
        let tree = SortedPackedIntervalRTree<LineSegment>()
        let g = geom!
        isEmpty = g.isEmpty()
        if !isEmpty {
            for line in LinearComponentExtracter.getLines(g) where line.isClosed() {
                let pts = line.points
                for i in stride(from: 1, to: pts.count, by: 1) {
                    let seg = LineSegment(pts[i - 1], pts[i])
                    tree.insert(javaMin(seg.p0.y, seg.p1.y), javaMax(seg.p0.y, seg.p1.y), seg)
                }
            }
        }
        index = tree
        geom = nil
    }
}
