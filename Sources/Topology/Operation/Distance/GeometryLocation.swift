/// A point of a geometry's component: the component, the index of its
/// segment (`insideArea` for a point inside a polygon) and the point:
/// JTS's `GeometryLocation`.
public struct GeometryLocation {
    public static let insideArea = -1

    public let component: Geometry
    public let segmentIndex: Int
    public let coordinate: Coordinate

    public init(_ component: Geometry, _ segIndex: Int, _ pt: Coordinate) {
        self.component = component
        segmentIndex = segIndex
        coordinate = pt
    }

    public init(_ component: Geometry, _ pt: Coordinate) { self.init(component, GeometryLocation.insideArea, pt) }

    public var isInsideArea: Bool { segmentIndex == GeometryLocation.insideArea }
}
