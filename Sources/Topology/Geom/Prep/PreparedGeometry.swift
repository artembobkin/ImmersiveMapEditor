/// A geometry prepared for many predicates against other geometries, its
/// indexes made once: JTS's `PreparedGeometry`, and its factory as GEOS
/// 3.13 chooses the kind (points, lines, polygons, else the basic one).
public protocol PreparedGeometry: AnyObject {
    var geometry: Geometry { get }
    func contains(_ g: Geometry) throws -> Bool
    func intersects(_ g: Geometry) throws -> Bool
    func within(_ g: Geometry) throws -> Bool
    func covers(_ g: Geometry) throws -> Bool
    func containsProperly(_ g: Geometry) throws -> Bool
}

public enum PreparedGeometryFactory {
    public static func prepare(_ geom: Geometry) -> PreparedGeometry {
        switch geom {
        case is Point, is MultiPoint: return PreparedPoint(geom)
        case is LineString, is MultiLineString: return PreparedLineString(geom)
        case is Polygon, is MultiPolygon: return PreparedPolygon(geom)
        default: return BasicPreparedGeometry(geom)
        }
    }
}
