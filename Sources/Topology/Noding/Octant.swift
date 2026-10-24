/// The octant of a direction: JTS's `Octant`, 0 to 7 counter-clockwise from
/// east.
public enum Octant {
    public static func octant(_ dx: Double, _ dy: Double) -> Int {
        precondition(!(dx == 0.0 && dy == 0.0), "Cannot compute the octant for point ( \(dx), \(dy) )")
        let adx = abs(dx), ady = abs(dy)
        if dx >= 0 {
            if dy >= 0 { return adx >= ady ? 0 : 1 }
            return adx >= ady ? 7 : 6
        }
        if dy >= 0 { return adx >= ady ? 3 : 2 }
        return adx >= ady ? 4 : 5
    }

    public static func octant(_ p0: Coordinate, _ p1: Coordinate) -> Int {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        precondition(!(dx == 0.0 && dy == 0.0), "Cannot compute the octant for two identical points \(p0)")
        return octant(dx, dy)
    }
}
