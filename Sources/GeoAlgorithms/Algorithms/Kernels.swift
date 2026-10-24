/// geo's kernels for `f64`: the `Orientation` of three points and the `RobustKernel` that
/// decides it with robust's adaptive `orient2d`.

/// The orientation of three points. The cases are declared in geo's order, which its derived
/// `Ord` follows.
public enum GeoOrientation: Int, Sendable, Comparable {
    case counterClockwise
    case clockwise
    case collinear

    public static func < (lhs: GeoOrientation, rhs: GeoOrientation) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// `Orientation::as_ordering`: counterclockwise is `Less`, clockwise `Greater`.
    var asOrdering: RustOrdering {
        switch self {
        case .counterClockwise: return .less
        case .clockwise: return .greater
        case .collinear: return .equal
        }
    }
}

/// geo's `RobustKernel`, the kernel `f64` uses (`<f64 as HasKernel>::Ker`).
public enum RobustKernel {
    /// The orientation of `p`, `q`, `r`: counterclockwise if `r` lies left of `p -> q`.
    public static func orient2d(_ p: GeoCoord, _ q: GeoCoord, _ r: GeoCoord) -> GeoOrientation {
        let orientation = Robust.orient2d(p, q, r)
        if orientation < 0 {
            return .clockwise
        } else if orientation > 0 {
            return .counterClockwise
        } else {
            return .collinear
        }
    }

    /// `Kernel::square_euclidean_distance`.
    public static func squareEuclideanDistance(_ p: GeoCoord, _ q: GeoCoord) -> Double {
        (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)
    }

    /// `Kernel::dot_product_sign`: the sign of `u . v`, through `orient2d`.
    public static func dotProductSign(_ u: GeoCoord, _ v: GeoCoord) -> GeoOrientation {
        let vdash = GeoCoord(x: 0 - v.y, y: v.x)
        return orient2d(.zero, u, vdash)
    }
}
