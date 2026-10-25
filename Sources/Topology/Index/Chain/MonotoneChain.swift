/// A run of segments of a line all heading into one quadrant, so its
/// envelope is the envelope of its ends and any part of it is found by
/// bisection: JTS's `MonotoneChain`. The context is the segment string it
/// belongs to.
public final class MonotoneChain {
    let pts: [Coordinate]
    public let start: Int
    public let end: Int
    public let context: SegmentString?
    public var id = 0
    private var env: Envelope?

    public init(_ pts: [Coordinate], _ start: Int, _ end: Int, _ context: SegmentString?) {
        self.pts = pts
        self.start = start
        self.end = end
        self.context = context
    }

    /// The envelope, expanded the first time it is asked for (and kept).
    public func getEnvelope(_ expansionDistance: Double = 0.0) -> Envelope {
        if let env { return env }
        var e = Envelope(pts[start], pts[end])
        if expansionDistance > 0.0 { e.expandBy(expansionDistance) }
        env = e
        return e
    }

    public func getLineSegment(_ index: Int) -> LineSegment { LineSegment(pts[index], pts[index + 1]) }
    public func getCoordinates() -> [Coordinate] { Array(pts[start...end]) }

    /// Every segment whose envelope may meet `searchEnv`, by its start index.
    public func select(_ searchEnv: Envelope, _ select: (MonotoneChain, Int) -> Void) {
        computeSelect(searchEnv, start, end, select)
    }

    func computeSelect(_ searchEnv: Envelope, _ start0: Int, _ end0: Int, _ select: (MonotoneChain, Int) -> Void) {
        let p0 = pts[start0], p1 = pts[end0]
        if end0 - start0 == 1 {
            select(self, start0)
            return
        }
        if !searchEnv.intersects(p0, p1) { return }
        let mid = (start0 + end0) / 2
        if start0 < mid { computeSelect(searchEnv, start0, mid, select) }
        if mid < end0 { computeSelect(searchEnv, mid, end0, select) }
    }

    /// Every pair of segments of the two chains whose envelopes may meet.
    public func computeOverlaps(_ mc: MonotoneChain, _ overlapTolerance: Double = 0.0,
                                _ overlap: (MonotoneChain, Int, MonotoneChain, Int) -> Void) {
        computeOverlaps(start, end, mc, mc.start, mc.end, overlapTolerance, overlap)
    }

    func computeOverlaps(_ start0: Int, _ end0: Int, _ mc: MonotoneChain, _ start1: Int, _ end1: Int,
                         _ tolerance: Double, _ overlap: (MonotoneChain, Int, MonotoneChain, Int) -> Void) {
        if end0 - start0 == 1 && end1 - start1 == 1 {
            overlap(self, start0, mc, start1)
            return
        }
        if !overlaps(start0, end0, mc, start1, end1, tolerance) { return }
        let mid0 = (start0 + end0) / 2, mid1 = (start1 + end1) / 2
        if start0 < mid0 {
            if start1 < mid1 { computeOverlaps(start0, mid0, mc, start1, mid1, tolerance, overlap) }
            if mid1 < end1 { computeOverlaps(start0, mid0, mc, mid1, end1, tolerance, overlap) }
        }
        if mid0 < end0 {
            if start1 < mid1 { computeOverlaps(mid0, end0, mc, start1, mid1, tolerance, overlap) }
            if mid1 < end1 { computeOverlaps(mid0, end0, mc, mid1, end1, tolerance, overlap) }
        }
    }

    func overlaps(_ start0: Int, _ end0: Int, _ mc: MonotoneChain, _ start1: Int, _ end1: Int, _ tolerance: Double) -> Bool {
        if tolerance > 0.0 { return MonotoneChain.overlaps(pts[start0], pts[end0], mc.pts[start1], mc.pts[end1], tolerance) }
        return Envelope.intersects(pts[start0], pts[end0], mc.pts[start1], mc.pts[end1])
    }

    static func overlaps(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate, _ tolerance: Double) -> Bool {
        var minq = cxxMin(q1.x, q2.x), maxq = cxxMax(q1.x, q2.x)
        var minp = cxxMin(p1.x, p2.x), maxp = cxxMax(p1.x, p2.x)
        if minp > maxq + tolerance { return false }
        if maxp < minq - tolerance { return false }
        minq = cxxMin(q1.y, q2.y); maxq = cxxMax(q1.y, q2.y)
        minp = cxxMin(p1.y, p2.y); maxp = cxxMax(p1.y, p2.y)
        if minp > maxq + tolerance { return false }
        if maxp < minq - tolerance { return false }
        return true
    }
}
