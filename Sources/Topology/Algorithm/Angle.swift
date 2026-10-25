import Darwin

/// Angles of vectors and between them, in radians: JTS's `Angle`, the
/// functions the buffer uses. The sine and cosine of an angle are snapped
/// to zero below 5e-16, as in both.
public enum Angle {
    public static let piTimes2 = 2.0 * Double.pi
    public static let piOver2 = Double.pi / 2.0
    public static let piOver4 = Double.pi / 4.0

    /// The angle of the vector from `p0` to `p1`, in (-pi, pi].
    public static func angle(_ p0: Coordinate, _ p1: Coordinate) -> Double {
        atan2(p1.y - p0.y, p1.x - p0.x)
    }

    /// The oriented angle from `tail`-`tip1` to `tail`-`tip2`, in (-pi, pi].
    public static func angleBetweenOriented(_ tip1: Coordinate, _ tail: Coordinate, _ tip2: Coordinate) -> Double {
        let a1 = angle(tail, tip1)
        let a2 = angle(tail, tip2)
        let angDel = a2 - a1
        if angDel <= -Double.pi { return angDel + piTimes2 }
        if angDel > Double.pi { return angDel - piTimes2 }
        return angDel
    }

    /// The angle in (-pi, pi].
    public static func normalize(_ angle: Double) -> Double {
        var a = angle
        while a > Double.pi { a -= piTimes2 }
        while a <= -Double.pi { a += piTimes2 }
        return a
    }

    public static func cosSnap(_ ang: Double) -> Double {
        let res = cos(ang)
        return abs(res) < 5e-16 ? 0.0 : res
    }

    public static func sinSnap(_ ang: Double) -> Double {
        let res = sin(ang)
        return abs(res) < 5e-16 ? 0.0 : res
    }
}
