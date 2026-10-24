import Darwin

/// A point in the plane: JTS's `Coordinate`, in two dimensions only (the
/// package's geometry is planar, and GEOS is called with XY coordinates).
///
/// Equality is JTS's `equals2D` (so `0.0 == -0.0`, and a NaN is equal to
/// nothing), the order its `compareTo`: by x, then by y.
public struct Coordinate: Hashable, Comparable, CustomStringConvertible, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    /// The null coordinate of JTS (both ordinates NaN), for an absent value.
    public static let null = Coordinate(.nan, .nan)

    public var isNull: Bool { x.isNaN && y.isNaN }

    public func equals2D(_ o: Coordinate) -> Bool { x == o.x && y == o.y }

    /// Equal within `tolerance` on each ordinate (`NumberUtil.equalsWithTolerance`).
    public func equals2D(_ o: Coordinate, tolerance: Double) -> Bool {
        abs(x - o.x) <= tolerance && abs(y - o.y) <= tolerance
    }

    public func compareTo(_ o: Coordinate) -> Int {
        if x < o.x { return -1 }
        if x > o.x { return 1 }
        if y < o.y { return -1 }
        if y > o.y { return 1 }
        return 0
    }

    /// The distance to `c`. JTS 1.20 takes `Math.hypot(dx, dy)`, GEOS 3.13
    /// `sqrt(dx * dx + dy * dy)` with the sum fused: GEOS's, which the
    /// centroids and interior points of lines match.
    public func distance(_ c: Coordinate) -> Double {
        let dx = x - c.x
        let dy = y - c.y
        return fusedAdd(dx, dx, dy * dy).squareRoot()
    }

    public static func == (a: Coordinate, b: Coordinate) -> Bool { a.x == b.x && a.y == b.y }
    public static func < (a: Coordinate, b: Coordinate) -> Bool { a.compareTo(b) < 0 }

    public func hash(into h: inout Hasher) {
        // Equal coordinates hash alike, -0.0 as 0.0.
        h.combine(x == 0 ? 0 : x)
        h.combine(y == 0 ? 0 : y)
    }

    /// JTS's `Coordinate.hashCode`, for structures whose order follows it.
    public var javaHashCode: Int32 {
        var result: Int32 = 17
        result = 37 &* result &+ Coordinate.javaHashCode(x)
        result = 37 &* result &+ Coordinate.javaHashCode(y)
        return result
    }

    public static func javaHashCode(_ v: Double) -> Int32 {
        // Double.doubleToLongBits: every NaN is the canonical one.
        let f = v.isNaN ? Int64(0x7ff8_0000_0000_0000) : Int64(bitPattern: v.bitPattern)
        return Int32(truncatingIfNeeded: f ^ Int64(bitPattern: UInt64(bitPattern: f) >> 32))
    }

    public var description: String { "(\(x), \(y))" }
}
