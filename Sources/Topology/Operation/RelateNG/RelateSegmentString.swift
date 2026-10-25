/// A line or ring of a geometry for RelateNG, its repeated points removed,
/// with which geometry and element it is of, and how to make the section
/// of it at a node: JTS's `RelateSegmentString`.
final class RelateSegmentString: SegmentString {
    let isA: Bool
    let dimension: Int
    let id: Int
    let ringId: Int
    unowned let inputGeom: RelateGeometry
    let parentPolygonal: Geometry?

    static func createLine(_ pts: [Coordinate], _ isA: Bool, _ elementId: Int, _ parent: RelateGeometry) -> RelateSegmentString {
        RelateSegmentString(CoordinateArrays.removeRepeatedPoints(pts), isA, Dimension.l, elementId, -1, nil, parent)
    }

    static func createRing(_ pts: [Coordinate], _ isA: Bool, _ elementId: Int, _ ringId: Int, _ poly: Geometry?,
                           _ parent: RelateGeometry) -> RelateSegmentString {
        RelateSegmentString(CoordinateArrays.removeRepeatedPoints(pts), isA, Dimension.a, elementId, ringId, poly, parent)
    }

    private init(_ pts: [Coordinate], _ isA: Bool, _ dimension: Int, _ id: Int, _ ringId: Int, _ poly: Geometry?,
                 _ inputGeom: RelateGeometry) {
        self.isA = isA
        self.dimension = dimension
        self.id = id
        self.ringId = ringId
        parentPolygonal = poly
        self.inputGeom = inputGeom
        super.init(pts, nil)
    }


    func createNodeSection(_ segIndex: Int, _ intPt: Coordinate) -> NodeSection {
        let isNodeAtVertex = intPt.equals2D(pts[segIndex]) || intPt.equals2D(pts[segIndex + 1])
        return NodeSection(isA, dimension, id, ringId, parentPolygonal, isNodeAtVertex,
                           prevVertex(segIndex, intPt), intPt, nextVertex(segIndex, intPt))
    }

    private func prevVertex(_ segIndex: Int, _ pt: Coordinate) -> Coordinate? {
        let segStart = pts[segIndex]
        if !segStart.equals2D(pt) { return segStart }
        if segIndex > 0 { return pts[segIndex - 1] }
        if isClosed() { return prevInRing(segIndex) }
        return nil
    }

    private func nextVertex(_ segIndex: Int, _ pt: Coordinate) -> Coordinate? {
        let segEnd = pts[segIndex + 1]
        if !segEnd.equals2D(pt) { return segEnd }
        if segIndex < pts.count - 2 { return pts[segIndex + 2] }
        if isClosed() { return nextInRing(segIndex + 1) }
        return nil
    }

    /// Whether the segment holds the point for noding: a segment's end
    /// belongs to the next segment, except at the end of an open line.
    func isContainingSegment(_ segIndex: Int, _ pt: Coordinate) -> Bool {
        if pt.equals2D(pts[segIndex]) { return true }
        if pt.equals2D(pts[segIndex + 1]) {
            let isFinalSegment = segIndex == pts.count - 2
            if isClosed() || !isFinalSegment { return false }
            return true
        }
        return true
    }
}
