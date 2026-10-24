/// The intersection of lines: JTS's `Intersection`.
public enum Intersection {
    /// The intersection point of the lines through `p1`-`p2` and `q1`-`q2`,
    /// nil when they are parallel. JTS 1.20 computes it in DD.
    public static func intersection(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Coordinate? {
        CGAlgorithmsDD.intersection(p1, p2, q1, q2)
    }

    /// The same in doubles, about the middle of the segments' common envelope.
    public static func intersectionFP(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Coordinate? {
        let minX0 = p1.x < p2.x ? p1.x : p2.x
        let minY0 = p1.y < p2.y ? p1.y : p2.y
        let maxX0 = p1.x > p2.x ? p1.x : p2.x
        let maxY0 = p1.y > p2.y ? p1.y : p2.y
        let minX1 = q1.x < q2.x ? q1.x : q2.x
        let minY1 = q1.y < q2.y ? q1.y : q2.y
        let maxX1 = q1.x > q2.x ? q1.x : q2.x
        let maxY1 = q1.y > q2.y ? q1.y : q2.y
        let intMinX = minX0 > minX1 ? minX0 : minX1
        let intMaxX = maxX0 < maxX1 ? maxX0 : maxX1
        let intMinY = minY0 > minY1 ? minY0 : minY1
        let intMaxY = maxY0 < maxY1 ? maxY0 : maxY1
        let midx = (intMinX + intMaxX) / 2.0
        let midy = (intMinY + intMaxY) / 2.0
        let p1x = p1.x - midx, p1y = p1.y - midy
        let p2x = p2.x - midx, p2y = p2.y - midy
        let q1x = q1.x - midx, q1y = q1.y - midy
        let q2x = q2.x - midx, q2y = q2.y - midy
        let px = p1y - p2y
        let py = p2x - p1x
        let pw = fusedSub(p1x, p2y, p2x * p1y)
        let qx = q1y - q2y
        let qy = q2x - q1x
        let qw = fusedSub(q1x, q2y, q2x * q1y)
        let x = fusedSub(py, qw, qy * pw)
        let y = fusedSub(qx, pw, px * qw)
        let w = fusedSub(px, qy, qx * py)
        let xInt = x / w
        let yInt = y / w
        if xInt.isNaN || xInt.isInfinite || yInt.isNaN || yInt.isInfinite { return nil }
        return Coordinate(xInt + midx, yInt + midy)
    }

    /// Where a line crosses a segment, nil when it does not.
    public static func lineSegment(_ line1: Coordinate, _ line2: Coordinate, _ seg1: Coordinate, _ seg2: Coordinate) -> Coordinate? {
        let orientS1 = Orientation.index(line1, line2, seg1)
        if orientS1 == 0 { return seg1 }
        let orientS2 = Orientation.index(line1, line2, seg2)
        if orientS2 == 0 { return seg2 }
        if (orientS1 > 0 && orientS2 > 0) || (orientS1 < 0 && orientS2 < 0) { return nil }
        if let p = intersection(line1, line2, seg1, seg2) { return p }
        let dist1 = Distance.pointToLinePerpendicular(seg1, line1, line2)
        let dist2 = Distance.pointToLinePerpendicular(seg2, line1, line2)
        if dist1 < dist2 { return seg1 }
        return seg2
    }
}
