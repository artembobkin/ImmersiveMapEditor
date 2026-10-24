/// The order of edges around a node by angle, and the tests polygon
/// topology makes with it: JTS's `PolygonNodeTopology`. Angles are compared
/// by quadrant, then by orientation, counter-clockwise from the positive x
/// axis, so the comparison is exact.
public enum PolygonNodeTopology {
    /// Whether the edges `b0`, `b1` of a node cross the edges `a0`, `a1`
    /// (one on each side), not merely touch them.
    public static func isCrossing(_ nodePt: Coordinate, _ a0: Coordinate, _ a1: Coordinate, _ b0: Coordinate, _ b1: Coordinate) -> Bool {
        var aLo = a0, aHi = a1
        if isAngleGreater(nodePt, aLo, aHi) {
            aLo = a1
            aHi = a0
        }
        let compBetween0 = compareBetween(nodePt, b0, aLo, aHi)
        if compBetween0 == 0 { return false }
        let compBetween1 = compareBetween(nodePt, b1, aLo, aHi)
        if compBetween1 == 0 { return false }
        return compBetween0 != compBetween1
    }

    /// Whether `b` is inside the corner `a0`, `a1` of a ring whose interior
    /// lies to the right of its direction.
    public static func isInteriorSegment(_ nodePt: Coordinate, _ a0: Coordinate, _ a1: Coordinate, _ b: Coordinate) -> Bool {
        var aLo = a0, aHi = a1
        var isInteriorBetween = true
        if isAngleGreater(nodePt, aLo, aHi) {
            aLo = a1
            aHi = a0
            isInteriorBetween = false
        }
        let isBetween = isBetween(nodePt, b, aLo, aHi)
        return (isBetween && isInteriorBetween) || (!isBetween && !isInteriorBetween)
    }

    private static func isBetween(_ origin: Coordinate, _ p: Coordinate, _ e0: Coordinate, _ e1: Coordinate) -> Bool {
        if !isAngleGreater(origin, p, e0) { return false }
        return !isAngleGreater(origin, p, e1)
    }

    private static func compareBetween(_ origin: Coordinate, _ p: Coordinate, _ e0: Coordinate, _ e1: Coordinate) -> Int {
        let comp0 = compareAngle(origin, p, e0)
        if comp0 == 0 { return 0 }
        let comp1 = compareAngle(origin, p, e1)
        if comp1 == 0 { return 0 }
        if comp0 > 0 && comp1 < 0 { return 1 }
        return -1
    }

    private static func isAngleGreater(_ origin: Coordinate, _ p: Coordinate, _ q: Coordinate) -> Bool {
        let quadrantP = quadrant(origin, p), quadrantQ = quadrant(origin, q)
        if quadrantP > quadrantQ { return true }
        if quadrantP < quadrantQ { return false }
        return Orientation.index(origin, q, p) == Orientation.counterclockwise
    }

    /// 1, 0 or -1 as the angle of `p` about `origin` is greater, equal or
    /// less than that of `q`.
    public static func compareAngle(_ origin: Coordinate, _ p: Coordinate, _ q: Coordinate) -> Int {
        let quadrantP = quadrant(origin, p), quadrantQ = quadrant(origin, q)
        if quadrantP > quadrantQ { return 1 }
        if quadrantP < quadrantQ { return -1 }
        switch Orientation.index(origin, q, p) {
        case Orientation.counterclockwise: return 1
        case Orientation.clockwise: return -1
        default: return 0
        }
    }

    private static func quadrant(_ origin: Coordinate, _ p: Coordinate) -> Int {
        Quadrant.quadrant(p.x - origin.x, p.y - origin.y)
    }
}
