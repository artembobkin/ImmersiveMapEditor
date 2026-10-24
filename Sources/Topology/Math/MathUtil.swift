/// Small numeric helpers: JTS's `MathUtil`.
public enum MathUtil {
    /// The least of four values, the first of equals (NaN only if first).
    public static func min(_ v1: Double, _ v2: Double, _ v3: Double, _ v4: Double) -> Double {
        var m = v1
        if v2 < m { m = v2 }
        if v3 < m { m = v3 }
        if v4 < m { m = v4 }
        return m
    }

    public static func max(_ v1: Double, _ v2: Double, _ v3: Double) -> Double {
        var m = v1
        if v2 > m { m = v2 }
        if v3 > m { m = v3 }
        return m
    }

    public static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        if x < lo { return lo }
        if x > hi { return hi }
        return x
    }

    public static func clamp(_ x: Int, _ lo: Int, _ hi: Int) -> Int {
        if x < lo { return lo }
        if x > hi { return hi }
        return x
    }
}
