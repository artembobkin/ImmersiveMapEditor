/// The area of rings: JTS's `Area`, by the shoelace formula with the ring
/// moved to its first x, which keeps precision.
public enum Area {
    public static func ofRing(_ ring: [Coordinate]) -> Double { abs(ofRingSigned(ring)) }

    /// The signed area: positive when the ring is clockwise.
    public static func ofRingSigned(_ ring: [Coordinate]) -> Double {
        let n = ring.count
        if n < 3 { return 0.0 }
        var p0y = 0.0
        var p1 = ring[0]
        var p2 = ring[1]
        let x0 = p1.x
        p2.x -= x0
        var sum = 0.0
        for i in 1..<(n - 1) {
            p0y = p1.y
            p1 = p2
            p2 = ring[i + 1]
            p2.x -= x0
            // sum += p1.x * (p0.y - p2.y), fused as GEOS's.
            sum = fusedAdd(p1.x, p0y - p2.y, sum)
        }
        return sum / 2.0
    }
}
