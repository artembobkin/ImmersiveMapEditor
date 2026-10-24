/// A port of the Rust crate robust 1.2.0: Shewchuk's adaptive precision orientation predicate,
/// with the same error bounds and the same expansion arithmetic. Only `orient2d` is ported, the
/// one predicate geo's `RobustKernel` uses.

public enum Robust {
    // Precomputed from `exactinit` of Shewchuk's C source, as robust has them.
    static let splitter: Double = 134_217_729
    static let epsilon: Double = 0.000_000_000_000_000_111_022_302_462_515_65
    static let resultErrBound: Double = (3.0 + 8.0 * epsilon) * epsilon
    static let ccwErrBoundB: Double = (2.0 + 12.0 * epsilon) * epsilon
    static let ccwErrBoundC: Double = (9.0 + 64.0 * epsilon) * epsilon * epsilon

    /// Returns a positive value if `pa`, `pb` and `pc` occur in counterclockwise order (`pc` lies
    /// to the left of the directed line from `pa` to `pb`), a negative value if they occur in
    /// clockwise order, and zero if they are collinear.
    public static func orient2d(_ pa: GeoCoord, _ pb: GeoCoord, _ pc: GeoCoord) -> Double {
        let detleft = (pa.x - pc.x) * (pb.y - pc.y)
        let detright = (pa.y - pc.y) * (pb.x - pc.x)
        let det = detleft - detright

        // The error bound needs only one branch on the likely path (Ozaki et al.). The underflow
        // guard is omitted as in robust.
        let detsum = abs(detleft + detright)
        let theta: Double = 3.3306690621773722e-16
        let errbound = theta * detsum
        if det >= errbound || -det >= errbound {
            return det
        }
        return orient2dAdapt(pa, pb, pc, detsum)
    }

    static func orient2dAdapt(_ pa: GeoCoord, _ pb: GeoCoord, _ pc: GeoCoord, _ detsum: Double) -> Double {
        let acx = pa.x - pc.x
        let bcx = pb.x - pc.x
        let acy = pa.y - pc.y
        let bcy = pb.y - pc.y

        let (detleft, detlefttail) = twoProduct(acx, bcy)
        let (detright, detrighttail) = twoProduct(acy, bcx)

        let (b3, b2, b1, b0) = twoTwoDiff(detleft, detlefttail, detright, detrighttail)
        let bExp = [b0, b1, b2, b3]

        var det = estimate(bExp)
        let errbound = ccwErrBoundB * detsum
        if det >= errbound || -det >= errbound {
            return det
        }

        let acxtail = twoDiffTail(pa.x, pc.x, acx)
        let bcxtail = twoDiffTail(pb.x, pc.x, bcx)
        let acytail = twoDiffTail(pa.y, pc.y, acy)
        let bcytail = twoDiffTail(pb.y, pc.y, bcy)

        if acxtail == 0.0 && acytail == 0.0 && bcxtail == 0.0 && bcytail == 0.0 {
            return det
        }

        let errboundC = ccwErrBoundC * detsum + resultErrBound * abs(det)
        det += (acx * bcytail + bcy * acxtail) - (acy * bcxtail + bcx * acytail)

        if det >= errboundC || -det >= errboundC {
            return det
        }

        var (s1, s0) = twoProduct(acxtail, bcy)
        var (t1, t0) = twoProduct(acytail, bcx)
        var (u3, u2, u1, u0) = twoTwoDiff(s1, s0, t1, t0)
        var u = [u0, u1, u2, u3]

        var c1 = [Double](repeating: 0, count: 8)
        let c1length = fastExpansionSumZeroElim(bExp[...], u[...], &c1)

        (s1, s0) = twoProduct(acx, bcytail)
        (t1, t0) = twoProduct(acy, bcxtail)
        (u3, u2, u1, u0) = twoTwoDiff(s1, s0, t1, t0)
        u = [u0, u1, u2, u3]

        var c2 = [Double](repeating: 0, count: 12)
        let c2length = fastExpansionSumZeroElim(c1[..<c1length], u[...], &c2)

        (s1, s0) = twoProduct(acxtail, bcytail)
        (t1, t0) = twoProduct(acytail, bcxtail)
        (u3, u2, u1, u0) = twoTwoDiff(s1, s0, t1, t0)
        u = [u0, u1, u2, u3]
        var d = [Double](repeating: 0, count: 16)
        let dlength = fastExpansionSumZeroElim(c2[..<c2length], u[...], &d)
        return d[dlength - 1]
    }
}
