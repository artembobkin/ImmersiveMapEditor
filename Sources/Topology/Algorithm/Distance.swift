/// Distances between points, segments and lines: JTS's `Distance`. Sums of
/// products fused as GEOS's (`Fused.swift`).
public enum Distance {
    public static func segmentToSegment(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate, _ d: Coordinate) -> Double {
        if a == b { return pointToSegment(a, c, d) }
        if c == d { return pointToSegment(d, a, b) }
        var noIntersection = false
        if !Envelope.intersects(a, b, c, d) {
            noIntersection = true
        } else {
            let denom = fusedSub(b.x - a.x, d.y - c.y, (b.y - a.y) * (d.x - c.x))
            if denom == 0 {
                noIntersection = true
            } else {
                let rNum = fusedSub(a.y - c.y, d.x - c.x, (a.x - c.x) * (d.y - c.y))
                let sNum = fusedSub(a.y - c.y, b.x - a.x, (a.x - c.x) * (b.y - a.y))
                let s = sNum / denom
                let r = rNum / denom
                if (r < 0) || (r > 1) || (s < 0) || (s > 1) { noIntersection = true }
            }
        }
        if noIntersection {
            return MathUtil.min(pointToSegment(a, c, d), pointToSegment(b, c, d), pointToSegment(c, a, b), pointToSegment(d, a, b))
        }
        return 0.0
    }

    public static func pointToSegmentString(_ p: Coordinate, _ line: [Coordinate]) -> Double {
        precondition(!line.isEmpty, "Line array must contain at least one vertex")
        var minDistance = p.distance(line[0])
        if line.count > 1 {
            for i in 0..<(line.count - 1) {
                let d = pointToSegment(p, line[i], line[i + 1])
                if d < minDistance { minDistance = d }
            }
        }
        return minDistance
    }

    public static func pointToSegment(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        if a.x == b.x && a.y == b.y { return p.distance(a) }
        let len2 = fusedAdd(b.x - a.x, b.x - a.x, (b.y - a.y) * (b.y - a.y))
        let r = fusedAdd(p.x - a.x, b.x - a.x, (p.y - a.y) * (b.y - a.y)) / len2
        if r <= 0.0 { return p.distance(a) }
        if r >= 1.0 { return p.distance(b) }
        let s = fusedSub(a.y - p.y, b.x - a.x, (a.x - p.x) * (b.y - a.y)) / len2
        return abs(s) * len2.squareRoot()
    }

    public static func pointToLinePerpendicular(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let len2 = fusedAdd(b.x - a.x, b.x - a.x, (b.y - a.y) * (b.y - a.y))
        let s = fusedSub(a.y - p.y, b.x - a.x, (a.x - p.x) * (b.y - a.y)) / len2
        return abs(s) * len2.squareRoot()
    }

    public static func pointToLinePerpendicularSigned(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let len2 = fusedAdd(b.x - a.x, b.x - a.x, (b.y - a.y) * (b.y - a.y))
        let s = fusedSub(a.y - p.y, b.x - a.x, (a.x - p.x) * (b.y - a.y)) / len2
        return s * len2.squareRoot()
    }
}
