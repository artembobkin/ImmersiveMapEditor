/// Nodes the intersections of segments, snapped to the points already
/// kept, and the vertices within the snap tolerance of another segment:
/// JTS's `SnappingIntersectionAdder`.
public final class SnappingIntersectionAdder: SegmentIntersector {
    @exclusivity(unchecked) private var li = RobustLineIntersector()
    private let snapTolerance: Double
    private let snapPointIndex: SnappingPointIndex

    public init(_ snapTolerance: Double, _ snapPointIndex: SnappingPointIndex) {
        self.snapPointIndex = snapPointIndex
        self.snapTolerance = snapTolerance
    }

    override public func processIntersections(_ seg0: SegmentString, _ segIndex0: Int, _ seg1: SegmentString, _ segIndex1: Int) {
        if seg0 === seg1 && segIndex0 == segIndex1 { return }
        let p00 = seg0.getCoordinate(segIndex0), p01 = seg0.getCoordinate(segIndex0 + 1)
        let p10 = seg1.getCoordinate(segIndex1), p11 = seg1.getCoordinate(segIndex1 + 1)
        if !SnappingIntersectionAdder.isAdjacent(seg0, segIndex0, seg1, segIndex1) {
            li.computeIntersection(p00, p01, p10, p11)
            // Collinear (two point) intersections are noded below, by the vertices.
            if li.hasIntersection() && li.getIntersectionNum() == 1 {
                let snapPt = snapPointIndex.snap(li.getIntersection(0))
                (seg0 as! NodedSegmentString).addIntersection(snapPt, segIndex0)
                (seg1 as! NodedSegmentString).addIntersection(snapPt, segIndex1)
            }
        }
        processNearVertex(seg0, segIndex0, p00, seg1, segIndex1, p10, p11)
        processNearVertex(seg0, segIndex0, p01, seg1, segIndex1, p10, p11)
        processNearVertex(seg1, segIndex1, p10, seg0, segIndex0, p00, p01)
        processNearVertex(seg1, segIndex1, p11, seg0, segIndex0, p00, p01)
    }

    /// A vertex `p` of one segment near the interior of another is a node of both.
    private func processNearVertex(_ srcSS: SegmentString, _ srcIndex: Int, _ p: Coordinate, _ ss: SegmentString,
                                   _ segIndex: Int, _ p0: Coordinate, _ p1: Coordinate) {
        if p.distance(p0) < snapTolerance { return }
        if p.distance(p1) < snapTolerance { return }
        if Distance.pointToSegment(p, p0, p1) < snapTolerance {
            (ss as! NodedSegmentString).addIntersection(p, segIndex)
            (srcSS as! NodedSegmentString).addIntersection(p, srcIndex)
        }
    }

    /// Whether the segments follow each other in one string (a closed one
    /// wraps around).
    private static func isAdjacent(_ ss0: SegmentString, _ segIndex0: Int, _ ss1: SegmentString, _ segIndex1: Int) -> Bool {
        if ss0 !== ss1 { return false }
        if abs(segIndex0 - segIndex1) == 1 { return true }
        if ss0.isClosed() {
            let maxSegIndex = ss0.size() - 1
            if (segIndex0 == 0 && segIndex1 == maxSegIndex) || (segIndex1 == 0 && segIndex0 == maxSegIndex) { return true }
        }
        return false
    }

    override public func isDone() -> Bool { false }
}
