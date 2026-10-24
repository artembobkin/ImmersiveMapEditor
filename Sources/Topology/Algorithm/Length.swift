/// The length of lines: JTS's `Length`. JTS 1.20 adds `Math.hypot(dx, dy)`, GEOS
/// 3.13 `sqrt(dx * dx + dy * dy)` with the sum fused (it matches GEOS on every
/// random line of the parity tests, `hypot` does not): this is GEOS's.
public enum Length {
    public static func ofLine(_ pts: [Coordinate]) -> Double {
        let n = pts.count
        if n <= 1 { return 0.0 }
        var len = 0.0
        var x0 = pts[0].x, y0 = pts[0].y
        for i in 1..<n {
            let x1 = pts[i].x, y1 = pts[i].y
            let dx = x1 - x0, dy = y1 - y0
            len += fusedAdd(dx, dx, dy * dy).squareRoot()
            x0 = x1
            y0 = y1
        }
        return len
    }
}
