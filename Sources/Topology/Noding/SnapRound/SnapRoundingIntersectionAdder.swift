/// Finds the intersections of segments, and the vertices nearly on a
/// segment, for snap rounding: JTS's `SnapRoundingIntersectionAdder`.
public final class SnapRoundingIntersectionAdder: SegmentIntersector {
    @exclusivity(unchecked) var li = RobustLineIntersector()
    @exclusivity(unchecked) public private(set) var intersections: [Coordinate] = []
    let nearnessTol: Double

    public init(_ nearnessTol: Double) { self.nearnessTol = nearnessTol }

    override public func processIntersections(_ e0: SegmentString, _ segIndex0: Int, _ e1: SegmentString, _ segIndex1: Int) {
        if e0 === e1 && segIndex0 == segIndex1 { return }
        let p00 = e0.getCoordinate(segIndex0), p01 = e0.getCoordinate(segIndex0 + 1)
        let p10 = e1.getCoordinate(segIndex1), p11 = e1.getCoordinate(segIndex1 + 1)
        li.computeIntersection(p00, p01, p10, p11)
        if li.hasIntersection() && li.isInteriorIntersection() {
            for i in 0..<li.getIntersectionNum() { intersections.append(li.getIntersection(i)) }
            (e0 as! NodedSegmentString).addIntersections(li, segIndex0, 0)
            (e1 as! NodedSegmentString).addIntersections(li, segIndex1, 1)
            return
        }
        processNearVertex(p00, e1, segIndex1, p10, p11)
        processNearVertex(p01, e1, segIndex1, p10, p11)
        processNearVertex(p10, e0, segIndex0, p00, p01)
        processNearVertex(p11, e0, segIndex0, p00, p01)
    }

    func processNearVertex(_ p: Coordinate, _ edge: SegmentString, _ segIndex: Int, _ p0: Coordinate, _ p1: Coordinate) {
        if p.distance(p0) < nearnessTol { return }
        if p.distance(p1) < nearnessTol { return }
        if Distance.pointToSegment(p, p0, p1) < nearnessTol {
            intersections.append(p)
            (edge as! NodedSegmentString).addIntersection(p, segIndex)
        }
    }

    override public func isDone() -> Bool { false }
}
