/// The order of two points along a segment of a given octant: JTS's
/// `SegmentPointComparator`.
public enum SegmentPointComparator {
    public static func compare(_ octant: Int, _ p0: Coordinate, _ p1: Coordinate) -> Int {
        if p0.equals2D(p1) { return 0 }
        let xSign = relativeSign(p0.x, p1.x), ySign = relativeSign(p0.y, p1.y)
        switch octant {
        case 0: return compareValue(xSign, ySign)
        case 1: return compareValue(ySign, xSign)
        case 2: return compareValue(ySign, -xSign)
        case 3: return compareValue(-xSign, ySign)
        case 4: return compareValue(-xSign, -ySign)
        case 5: return compareValue(-ySign, -xSign)
        case 6: return compareValue(-ySign, xSign)
        case 7: return compareValue(xSign, -ySign)
        default: preconditionFailure("invalid octant value")
        }
    }

    public static func relativeSign(_ x0: Double, _ x1: Double) -> Int {
        if x0 < x1 { return -1 }
        if x0 > x1 { return 1 }
        return 0
    }

    static func compareValue(_ s0: Int, _ s1: Int) -> Int {
        if s0 < 0 { return -1 }
        if s0 > 0 { return 1 }
        if s1 < 0 { return -1 }
        if s1 > 0 { return 1 }
        return 0
    }
}
