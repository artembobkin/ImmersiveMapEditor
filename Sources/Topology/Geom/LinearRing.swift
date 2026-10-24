/// A closed line string, the ring of a polygon: JTS's `LinearRing`.
public final class LinearRing: LineString {
    public static let minimumValidRingSize = 3

    override init(_ points: [Coordinate], factory: GeometryFactory) {
        super.init(points, factory: factory)
        precondition(isEmpty() || super.isClosed(), "Points of LinearRing do not form a closed linestring")
        precondition(points.isEmpty || points.count >= LinearRing.minimumValidRingSize,
                     "Invalid number of points in LinearRing (found \(points.count) - must be 0 or >= 3)")
    }

    override var typeCode: TypeCode { .linearRing }
    override public func getGeometryType() -> String { "LinearRing" }
    override public func getBoundaryDimension() -> Int { Dimension.false }

    override public func isClosed() -> Bool {
        if isEmpty() { return true }
        return super.isClosed()
    }

    override func copyInternal() -> Geometry { LinearRing(points, factory: factory) }
    override func reverseInternal() -> Geometry { factory.createLinearRing(points.reversed()) }
}
