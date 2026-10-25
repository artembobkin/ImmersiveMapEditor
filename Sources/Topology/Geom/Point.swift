/// A point, or the empty point: JTS's `Point`.
public final class Point: Geometry {
    /// No coordinate when empty, else one.
    @exclusivity(unchecked) public internal(set) var coordinates: [Coordinate]

    init(_ coordinates: [Coordinate], factory: GeometryFactory) {
        precondition(coordinates.count <= 1)
        self.coordinates = coordinates
        super.init(factory: factory)
    }

    override var typeCode: TypeCode { .point }
    override public func getGeometryType() -> String { "Point" }
    override public func getCoordinates() -> [Coordinate] { coordinates }
    override public func getNumPoints() -> Int { coordinates.count }
    override public func isEmpty() -> Bool { coordinates.isEmpty }
    override public func getDimension() -> Int { 0 }
    override public func getBoundaryDimension() -> Int { Dimension.false }
    override public func getCoordinate() -> Coordinate? { coordinates.first }

    public func getX() -> Double {
        guard let c = coordinates.first else { preconditionFailure("getX called on empty Point") }
        return c.x
    }

    public func getY() -> Double {
        guard let c = coordinates.first else { preconditionFailure("getY called on empty Point") }
        return c.y
    }

    override public func getBoundary() -> Geometry { factory.createGeometryCollection() }

    override func computeEnvelopeInternal() -> Envelope {
        guard let c = coordinates.first else { return Envelope() }
        var e = Envelope()
        e.expandToInclude(c.x, c.y)
        return e
    }

    override public func equalsExact(_ other: Geometry, tolerance: Double) -> Bool {
        guard isEquivalentClass(other), let o = other as? Point else { return false }
        if isEmpty() && other.isEmpty() { return true }
        if isEmpty() != other.isEmpty() { return false }
        return equal(o.coordinates[0], coordinates[0], tolerance)
    }

    override func copyInternal() -> Geometry { Point(coordinates, factory: factory) }
    override func reverseInternal() -> Geometry { factory.createPoint(coordinates) }
    override public func normalize() {}

    override func compareToSameClass(_ other: Geometry) -> Int {
        coordinates[0].compareTo((other as! Point).coordinates[0])
    }
}
