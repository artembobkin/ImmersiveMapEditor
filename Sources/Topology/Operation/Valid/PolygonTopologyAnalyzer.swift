/// Analyzes the topology of polygonal geometry: whether its rings intersect
/// invalidly, and whether its interior is disconnected: JTS's
/// `PolygonTopologyAnalyzer`.
final class PolygonTopologyAnalyzer {
    /// Whether a ring is inside another, from its first point, or from the
    /// topology of its incident segment when that point is on the target.
    static func isRingNested(_ test: LinearRing, _ target: LinearRing) throws -> Bool {
        let p0 = test.getCoordinateN(0)
        let targetPts = target.points
        let loc = PointLocation.locateInRing(p0, targetPts)
        if loc == Location.exterior { return false }
        if loc == Location.interior { return true }
        // The start point is on the boundary of the ring: the topology at the
        // node tells whether the segment is inside or outside it.
        let p1 = findNonEqualVertex(test, p0)
        return try isIncidentSegmentInRing(p0, p1, targetPts)
    }

    private static func findNonEqualVertex(_ ring: LinearRing, _ p: Coordinate) -> Coordinate {
        var i = 1
        var next = ring.getCoordinateN(i)
        while next.equals2D(p) && i < ring.getNumPoints() - 1 {
            i += 1
            next = ring.getCoordinateN(i)
        }
        return next
    }

    private static func isIncidentSegmentInRing(_ p0: Coordinate, _ p1: Coordinate, _ ringPts: [Coordinate]) throws -> Bool {
        let index = intersectingSegIndex(ringPts, p0)
        if index < 0 { throw IllegalArgumentException("Segment vertex does not intersect ring") }
        var rPrev = findRingVertexPrev(ringPts, index, p0)
        var rNext = findRingVertexNext(ringPts, index, p0)
        // If the ring is not oriented as normalized, the corner is flipped.
        let isInteriorOnRight = !Orientation.isCCW(ringPts)
        if !isInteriorOnRight { swap(&rPrev, &rNext) }
        return PolygonNodeTopology.isInteriorSegment(p0, rPrev, rNext, p1)
    }

    private static func findRingVertexPrev(_ ringPts: [Coordinate], _ index: Int, _ node: Coordinate) -> Coordinate {
        var iPrev = index
        var prev = ringPts[iPrev]
        while node.equals2D(prev) {
            iPrev = ringIndexPrev(ringPts, iPrev)
            prev = ringPts[iPrev]
        }
        return prev
    }

    private static func findRingVertexNext(_ ringPts: [Coordinate], _ index: Int, _ node: Coordinate) -> Coordinate {
        //-- safe, since index is always the start of a ring segment
        var iNext = index + 1
        var next = ringPts[iNext]
        while node.equals2D(next) {
            iNext = ringIndexNext(ringPts, iNext)
            next = ringPts[iNext]
        }
        return next
    }

    private static func ringIndexPrev(_ ringPts: [Coordinate], _ index: Int) -> Int {
        if index == 0 { return ringPts.count - 2 }
        return index - 1
    }

    private static func ringIndexNext(_ ringPts: [Coordinate], _ index: Int) -> Int {
        if index >= ringPts.count - 2 { return 0 }
        return index + 1
    }

    private static func intersectingSegIndex(_ ringPts: [Coordinate], _ pt: Coordinate) -> Int {
        for i in 0..<(ringPts.count - 1) where PointLocation.isOnSegment(pt, ringPts[i], ringPts[i + 1]) {
            //-- check if pt is the start point of the next segment
            if pt.equals2D(ringPts[i + 1]) { return i + 1 }
            return i
        }
        return -1
    }

    /// The point where a ring intersects itself, if it does.
    static func findSelfIntersection(_ ring: LinearRing) -> Coordinate? {
        let ata = PolygonTopologyAnalyzer(ring, false)
        if ata.hasInvalidIntersection() { return ata.getInvalidLocation() }
        return nil
    }

    let isInvertedRingValid: Bool
    let intFinder: PolygonIntersectionAnalyzer
    @exclusivity(unchecked) var polyRings: [PolygonRing] = []
    @exclusivity(unchecked) var disconnectionPt: Coordinate?

    init(_ geom: Geometry, _ isInvertedRingValid: Bool) {
        self.isInvertedRingValid = isInvertedRingValid
        intFinder = PolygonIntersectionAnalyzer(isInvertedRingValid)
        analyze(geom)
    }

    func hasInvalidIntersection() -> Bool { intFinder.isInvalid() }
    func getInvalidCode() -> Int { intFinder.invalidCode }
    func getInvalidLocation() -> Coordinate? { intFinder.invalidLocation }

    func isInteriorDisconnected() -> Bool {
        // May already be set by a double-touching hole.
        if disconnectionPt != nil { return true }
        if isInvertedRingValid {
            checkInteriorDisconnectedBySelfTouch()
            if disconnectionPt != nil { return true }
        }
        checkInteriorDisconnectedByHoleCycle()
        if disconnectionPt != nil { return true }
        return false
    }

    func getDisconnectionLocation() -> Coordinate? { disconnectionPt }

    func checkInteriorDisconnectedByHoleCycle() {
        if !polyRings.isEmpty { disconnectionPt = PolygonRing.findHoleCycleLocation(polyRings) }
    }

    func checkInteriorDisconnectedBySelfTouch() {
        if !polyRings.isEmpty { disconnectionPt = PolygonRing.findInteriorSelfNode(polyRings) }
    }

    private func analyze(_ geom: Geometry) {
        if geom.isEmpty() { return }
        let segStrings = PolygonTopologyAnalyzer.createSegmentStrings(geom, isInvertedRingValid)
        polyRings = segStrings.compactMap { $0.getData() as? PolygonRing }
        let noder = MCIndexNoder(intFinder)
        noder.computeNodes(segStrings)
        if intFinder.hasDoubleTouch { disconnectionPt = intFinder.doubleTouchLocation }
    }

    private static func createSegmentStrings(_ geom: Geometry, _ isInvertedRingValid: Bool) -> [SegmentString] {
        var segStrings: [SegmentString] = []
        if let ring = geom as? LinearRing {
            segStrings.append(createSegString(ring, nil))
            return segStrings
        }
        for i in 0..<geom.getNumGeometries() {
            let poly = geom.getGeometryN(i) as! Polygon
            if poly.isEmpty() { continue }
            let hasHoles = poly.getNumInteriorRing() > 0
            //--- polygons with no holes do not need connected interior analysis
            var shellRing: PolygonRing?
            if hasHoles || isInvertedRingValid { shellRing = PolygonRing(poly.getExteriorRing()) }
            segStrings.append(createSegString(poly.getExteriorRing(), shellRing))
            for j in 0..<poly.getNumInteriorRing() {
                let hole = poly.getInteriorRingN(j)
                if hole.isEmpty() { continue }
                let holeRing = PolygonRing(hole, j, shellRing)
                segStrings.append(createSegString(hole, holeRing))
            }
        }
        return segStrings
    }

    private static func createSegString(_ ring: LinearRing, _ polyRing: PolygonRing?) -> SegmentString {
        var pts = ring.points
        //--- repeated points must be removed for accurate intersection detection
        if CoordinateArrays.hasRepeatedPoints(pts) { pts = CoordinateArrays.removeRepeatedPoints(pts) }
        return BasicSegmentString(pts, polyRing)
    }
}
