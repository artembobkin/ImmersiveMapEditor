/// Locates points on a lineal geometry with the point locator (JTS's
/// `IndexedPointOnLineLocator`, which has no index yet either).
final class IndexedPointOnLineLocator: PointOnGeometryLocator {
    private let inputGeom: Geometry

    init(_ geomLinear: Geometry) { inputGeom = geomLinear }

    func locate(_ p: Coordinate) -> Int {
        var locator = PointLocator()
        return locator.locate(p, inputGeom)
    }
}
