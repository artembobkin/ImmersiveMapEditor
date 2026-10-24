/// Points on segments, lines and rings: JTS's `PointLocation`.
public enum PointLocation {
    public static func isOnSegment(_ p: Coordinate, _ p0: Coordinate, _ p1: Coordinate) -> Bool {
        if !Envelope.intersects(p0, p1, p) { return false }
        if p.equals2D(p0) { return true }
        return Orientation.collinear == Orientation.index(p0, p1, p)
    }

    public static func isOnLine(_ p: Coordinate, _ line: [Coordinate]) -> Bool {
        if line.count < 2 { return false }
        for i in 1..<line.count where isOnSegment(p, line[i - 1], line[i]) { return true }
        return false
    }

    public static func isInRing(_ p: Coordinate, _ ring: [Coordinate]) -> Bool { locateInRing(p, ring) != Location.exterior }
    public static func locateInRing(_ p: Coordinate, _ ring: [Coordinate]) -> Int { RayCrossingCounter.locatePointInRing(p, ring) }
}
