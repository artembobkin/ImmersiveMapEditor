/// Finds the intersections of polygon rings that make a polygon invalid
/// (crossings, collinear overlaps, self-intersections of a ring) and records
/// the touches that may disconnect its interior: JTS's
/// `PolygonIntersectionAnalyzer`, a segment intersector of the noder.
final class PolygonIntersectionAnalyzer: SegmentIntersector {
    static let noInvalidIntersection = -1

    let isInvertedRingValid: Bool
    @exclusivity(unchecked) var li = RobustLineIntersector()
    @exclusivity(unchecked) private(set) var invalidCode = PolygonIntersectionAnalyzer.noInvalidIntersection
    @exclusivity(unchecked) private(set) var invalidLocation: Coordinate?
    @exclusivity(unchecked) private(set) var hasDoubleTouch = false
    @exclusivity(unchecked) private(set) var doubleTouchLocation: Coordinate?

    init(_ isInvertedRingValid: Bool) {
        self.isInvertedRingValid = isInvertedRingValid
    }

    override func isDone() -> Bool { isInvalid() || hasDoubleTouch }
    func isInvalid() -> Bool { invalidCode >= 0 }

    override func processIntersections(_ ss0: SegmentString, _ segIndex0: Int, _ ss1: SegmentString, _ segIndex1: Int) {
        // don't test a segment with itself
        let isSameSegString = ss0 === ss1
        let isSameSegment = isSameSegString && segIndex0 == segIndex1
        if isSameSegment { return }
        let code = findInvalidIntersection(ss0, segIndex0, ss1, segIndex1)
        // As in GEOS and JTS, the last invalid intersection found before the
        // noder stops is the one kept.
        if code != PolygonIntersectionAnalyzer.noInvalidIntersection {
            invalidCode = code
            invalidLocation = li.getIntersection(0)
        }
    }

    private func findInvalidIntersection(_ ss0: SegmentString, _ segIndex0: Int, _ ss1: SegmentString, _ segIndex1: Int) -> Int {
        let p00 = ss0.getCoordinate(segIndex0)
        let p01 = ss0.getCoordinate(segIndex0 + 1)
        let p10 = ss1.getCoordinate(segIndex1)
        let p11 = ss1.getCoordinate(segIndex1 + 1)
        li.computeIntersection(p00, p01, p10, p11)
        if !li.hasIntersection() { return PolygonIntersectionAnalyzer.noInvalidIntersection }
        let isSameSegString = ss0 === ss1
        // An intersection in the interior of both segments, or a collinear
        // one (which contains an interior one), is invalid.
        if li.isProper() || li.getIntersectionNum() >= 2 { return TopologyValidationError.selfIntersection }
        // Now there is exactly one intersection, at a vertex of at least one segment.
        let intPt = li.getIntersection(0)
        // Adjacent segments of a ring meet at their common end point: valid.
        let isAdjacentSegments = isSameSegString && PolygonIntersectionAnalyzer.isAdjacentInRing(ss0, segIndex0, segIndex1)
        if isAdjacentSegments { return PolygonIntersectionAnalyzer.noInvalidIntersection }
        // Under OGC semantics a ring cannot self-intersect.
        if isSameSegString && !isInvertedRingValid { return TopologyValidationError.ringSelfIntersection }
        // Points at the end of a segment are the start of the next: evaluated there.
        if intPt.equals2D(p01) || intPt.equals2D(p11) { return PolygonIntersectionAnalyzer.noInvalidIntersection }
        // The topology of a vertex intersection: the rings must not cross.
        var e00 = p00, e01 = p01
        if intPt.equals2D(p00) {
            e00 = PolygonIntersectionAnalyzer.prevCoordinateInRing(ss0, segIndex0)
            e01 = p01
        }
        var e10 = p10, e11 = p11
        if intPt.equals2D(p10) {
            e10 = PolygonIntersectionAnalyzer.prevCoordinateInRing(ss1, segIndex1)
            e11 = p11
        }
        let hasCrossing = PolygonNodeTopology.isCrossing(intPt, e00, e01, e10, e11)
        if hasCrossing { return TopologyValidationError.selfIntersection }
        // With inverted rings allowed, a self-touch is recorded, to check later
        // that it does not disconnect the interior.
        if isSameSegString && isInvertedRingValid {
            (ss0.getData() as! PolygonRing).addSelfTouch(intPt, e00, e01, e10, e11)
        }
        // Touches of rings of one polygon are recorded for the connected
        // interior check; a second touch of two rings is invalid.
        let isDoubleTouch = PolygonRing.addTouch(ss0.getData() as? PolygonRing, ss1.getData() as? PolygonRing, intPt)
        if isDoubleTouch && !isSameSegString {
            hasDoubleTouch = true
            doubleTouchLocation = intPt
        }
        return PolygonIntersectionAnalyzer.noInvalidIntersection
    }

    static func prevCoordinateInRing(_ ringSS: SegmentString, _ segIndex: Int) -> Coordinate {
        var prevIndex = segIndex - 1
        if prevIndex < 0 { prevIndex = ringSS.size() - 2 }
        return ringSS.getCoordinate(prevIndex)
    }

    static func isAdjacentInRing(_ ringSS: SegmentString, _ segIndex0: Int, _ segIndex1: Int) -> Bool {
        let delta = abs(segIndex1 - segIndex0)
        if delta <= 1 { return true }
        // A string of N vertices has segments 0 to N - 2: a delta of N - 2
        // or more joins its first and last segments.
        if delta >= ringSS.size() - 2 { return true }
        return false
    }
}
