/// Locates points in a geometry fixed in advance: JTS's
/// `PointOnGeometryLocator`.
public protocol PointOnGeometryLocator: AnyObject {
    /// The location of `p`: interior, boundary or exterior.
    func locate(_ p: Coordinate) -> Int
}
