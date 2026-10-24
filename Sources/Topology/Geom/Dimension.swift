/// The dimension of a geometry: JTS's `Dimension` values.
public enum Dimension {
    public static let p = 0
    public static let l = 1
    public static let a = 2
    /// The dimension of the empty set.
    public static let `false` = -1
    /// Any non-empty dimension, in patterns.
    public static let `true` = -2
    /// Any dimension, in patterns.
    public static let dontCare = -3
}
