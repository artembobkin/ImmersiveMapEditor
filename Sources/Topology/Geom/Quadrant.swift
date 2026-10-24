/// The quadrant of a direction: JTS's `Quadrant`, 0 to 3 counter-clockwise
/// from north-east.
public enum Quadrant {
    public static let ne = 0, nw = 1, sw = 2, se = 3

    public static func quadrant(_ dx: Double, _ dy: Double) -> Int {
        precondition(!(dx == 0.0 && dy == 0.0), "Cannot compute the quadrant for point ( \(dx), \(dy) )")
        if dx >= 0.0 { return dy >= 0.0 ? ne : se }
        return dy >= 0.0 ? nw : sw
    }

    public static func quadrant(_ p0: Coordinate, _ p1: Coordinate) -> Int {
        precondition(!(p1.x == p0.x && p1.y == p0.y), "Cannot compute the quadrant for two identical points \(p0)")
        if p1.x >= p0.x { return p1.y >= p0.y ? ne : se }
        return p1.y >= p0.y ? nw : sw
    }

    public static func isOpposite(_ q1: Int, _ q2: Int) -> Bool {
        if q1 == q2 { return false }
        return (q1 - q2 + 4) % 4 == 2
    }

    public static func commonHalfPlane(_ q1: Int, _ q2: Int) -> Int {
        if q1 == q2 { return q1 }
        if (q1 - q2 + 4) % 4 == 2 { return -1 }
        let lo = min(q1, q2), hi = max(q1, q2)
        if lo == 0 && hi == 3 { return 3 }
        return lo
    }

    public static func isInHalfPlane(_ quad: Int, _ halfPlane: Int) -> Bool {
        if halfPlane == se { return quad == se || quad == sw }
        return quad == halfPlane || quad == halfPlane + 1
    }

    public static func isNorthern(_ quad: Int) -> Bool { quad == ne || quad == nw }
}
