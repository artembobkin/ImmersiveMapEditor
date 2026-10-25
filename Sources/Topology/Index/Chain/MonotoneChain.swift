/// A run of segments of a line all heading into one quadrant, so its
/// envelope is the envelope of its ends and any part of it is found by
/// bisection: JTS's `MonotoneChain`. The context is the segment string it
/// belongs to.
public final class MonotoneChain {
    let pts: [Coordinate]
    public let start: Int
    public let end: Int
    public let context: SegmentString?
    @exclusivity(unchecked) public var id = 0
    @exclusivity(unchecked) private var env: Envelope?

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
        // The points of both chains read through buffers taken once, so the
        // recursion neither retains the arrays nor the chains.
        pts.withUnsafeBufferPointer { p in
            mc.pts.withUnsafeBufferPointer { q in
                MonotoneChain.computeOverlaps(self, p, start, end, mc, q, mc.start, mc.end, overlapTolerance, overlap)
            }
        }
    }

    /// `computeOverlaps` handing each pair of segments to a segment
    /// intersector with the chains' contexts, as the noders do: no closure
    /// between, so the contexts pass without reference counting.
    public func computeOverlaps(_ mc: MonotoneChain, _ overlapTolerance: Double, _ segInt: SegmentIntersector) {
        let ctx0 = context!, ctx1 = mc.context!
        pts.withUnsafeBufferPointer { p in
            mc.pts.withUnsafeBufferPointer { q in
                MonotoneChain.computeOverlaps(ctx0, p, start, end, ctx1, q, mc.start, mc.end, overlapTolerance, segInt)
            }
        }
    }

    private static func computeOverlaps(_ ctx0: SegmentString, _ p: UnsafeBufferPointer<Coordinate>, _ start0: Int, _ end0: Int,
                                        _ ctx1: SegmentString, _ q: UnsafeBufferPointer<Coordinate>, _ start1: Int, _ end1: Int,
                                        _ tolerance: Double, _ segInt: SegmentIntersector) {
        if end0 - start0 == 1 && end1 - start1 == 1 {
            segInt.processIntersections(ctx0, start0, ctx1, start1)
            return
        }
        let overlapping = tolerance > 0.0 ? overlaps(p[start0], p[end0], q[start1], q[end1], tolerance)
            : Envelope.intersects(p[start0], p[end0], q[start1], q[end1])
        if !overlapping { return }
        let mid0 = (start0 + end0) / 2, mid1 = (start1 + end1) / 2
        if start0 < mid0 {
            if start1 < mid1 { computeOverlaps(ctx0, p, start0, mid0, ctx1, q, start1, mid1, tolerance, segInt) }
            if mid1 < end1 { computeOverlaps(ctx0, p, start0, mid0, ctx1, q, mid1, end1, tolerance, segInt) }
        }
        if mid0 < end0 {
            if start1 < mid1 { computeOverlaps(ctx0, p, mid0, end0, ctx1, q, start1, mid1, tolerance, segInt) }
            if mid1 < end1 { computeOverlaps(ctx0, p, mid0, end0, ctx1, q, mid1, end1, tolerance, segInt) }
        }
    }

    private static func computeOverlaps(_ mc0: MonotoneChain, _ p: UnsafeBufferPointer<Coordinate>, _ start0: Int, _ end0: Int,
                                        _ mc1: MonotoneChain, _ q: UnsafeBufferPointer<Coordinate>, _ start1: Int, _ end1: Int,
                                        _ tolerance: Double, _ overlap: (MonotoneChain, Int, MonotoneChain, Int) -> Void) {
        if end0 - start0 == 1 && end1 - start1 == 1 {
            overlap(mc0, start0, mc1, start1)
            return
        }
        let overlapping = tolerance > 0.0 ? overlaps(p[start0], p[end0], q[start1], q[end1], tolerance)
            : Envelope.intersects(p[start0], p[end0], q[start1], q[end1])
        if !overlapping { return }
        let mid0 = (start0 + end0) / 2, mid1 = (start1 + end1) / 2
        if start0 < mid0 {
            if start1 < mid1 { computeOverlaps(mc0, p, start0, mid0, mc1, q, start1, mid1, tolerance, overlap) }
            if mid1 < end1 { computeOverlaps(mc0, p, start0, mid0, mc1, q, mid1, end1, tolerance, overlap) }
        }
        if mid0 < end0 {
            if start1 < mid1 { computeOverlaps(mc0, p, mid0, end0, mc1, q, start1, mid1, tolerance, overlap) }
            if mid1 < end1 { computeOverlaps(mc0, p, mid0, end0, mc1, q, mid1, end1, tolerance, overlap) }
        }
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
