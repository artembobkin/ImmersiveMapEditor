/// Robust geometric predicates in double-double arithmetic: JTS's
/// `CGAlgorithmsDD`. The orientation of three points is decided by a fast
/// floating point filter (Shewchuk's), and by DD only when the filter cannot.
public enum CGAlgorithmsDD {
    public static func orientationIndex(_ p1: Coordinate, _ p2: Coordinate, _ q: Coordinate) -> Int {
        orientationIndex(p1.x, p1.y, p2.x, p2.y, q.x, q.y)
    }

    /// 1 when `q` is left of `p1`-`p2` (counter-clockwise), -1 right, 0 on it.
    public static func orientationIndex(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double,
                                        _ qx: Double, _ qy: Double) -> Int {
        // GEOS throws here on a non-finite point (see `NonFinite`).
        if !qx.isFinite || !qy.isFinite { NonFinite.raise() }
        let index = orientationIndexFilter(p1x, p1y, p2x, p2y, qx, qy)
        if index <= 1 { return index }
        var dx1 = DD.valueOf(p2x)
        dx1.selfAdd(-p1x)
        var dy1 = DD.valueOf(p2y)
        dy1.selfAdd(-p1y)
        var dx2 = DD.valueOf(qx)
        dx2.selfAdd(-p2x)
        var dy2 = DD.valueOf(qy)
        dy2.selfAdd(-p2y)
        var det = dx1
        det.selfMultiply(dy2)
        dy1.selfMultiply(dx2)
        return det.selfSubtract(dy1).signum()
    }

    public static func signOfDet2x2(_ x1: DD, _ y1: DD, _ x2: DD, _ y2: DD) -> Int {
        var det = x1.multiply(y2)
        return det.selfSubtract(y1.multiply(x2)).signum()
    }

    public static func signOfDet2x2(_ dx1: Double, _ dy1: Double, _ dx2: Double, _ dy2: Double) -> Int {
        if !dx1.isFinite || !dy1.isFinite || !dx2.isFinite || !dy2.isFinite { NonFinite.raise() }
        return signOfDet2x2(DD(dx1), DD(dy1), DD(dx2), DD(dy2))
    }

    static let dpSafeEpsilon = 1e-15

    /// The orientation when plain doubles decide it safely, else 2.
    static func orientationIndexFilter(_ pax: Double, _ pay: Double, _ pbx: Double, _ pby: Double,
                                       _ pcx: Double, _ pcy: Double) -> Int {
        var detsum: Double
        let detleft = (pax - pcx) * (pby - pcy)
        let detright = (pay - pcy) * (pbx - pcx)
        let det = detleft - detright
        if detleft > 0.0 {
            if detright <= 0.0 { return signum(det) }
            detsum = detleft + detright
        } else if detleft < 0.0 {
            if detright >= 0.0 { return signum(det) }
            detsum = -detleft - detright
        } else {
            return signum(det)
        }
        let errbound = dpSafeEpsilon * detsum
        if (det >= errbound) || (-det >= errbound) { return signum(det) }
        return 2
    }

    static func signum(_ x: Double) -> Int {
        if x > 0 { return 1 }
        if x < 0 { return -1 }
        return 0
    }

    /// The intersection of the lines through `p1`-`p2` and `q1`-`q2` in DD,
    /// nil when they are parallel.
    public static func intersection(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> Coordinate? {
        var px = DD(p1.y); px.selfSubtract(p2.y)
        var py = DD(p2.x); py.selfSubtract(p1.x)
        var pw = DD(p1.x); pw.selfMultiply(p2.y)
        var pw2 = DD(p2.x); pw2.selfMultiply(p1.y)
        pw.selfSubtract(pw2)
        var qx = DD(q1.y); qx.selfSubtract(q2.y)
        var qy = DD(q2.x); qy.selfSubtract(q1.x)
        var qw = DD(q1.x); qw.selfMultiply(q2.y)
        var qw2 = DD(q2.x); qw2.selfMultiply(q1.y)
        qw.selfSubtract(qw2)
        var x = py.multiply(qw); x.selfSubtract(qy.multiply(pw))
        var y = qx.multiply(pw); y.selfSubtract(px.multiply(qw))
        var w = px.multiply(qy); w.selfSubtract(qx.multiply(py))
        let xInt = x.selfDivide(w).doubleValue
        let yInt = y.selfDivide(w).doubleValue
        if xInt.isNaN || xInt.isInfinite || yInt.isNaN || yInt.isInfinite { return nil }
        return Coordinate(xInt, yInt)
    }
}
