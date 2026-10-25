/// The union of points with a geometry of a higher dimension: the points
/// outside it, sorted and each once, added to it: JTS's
/// `PointGeometryUnion`, as GEOS 3.13 runs it (empty points skipped, the
/// points in GEOS's `std::set`, libc++'s tree, where a NaN coordinate is
/// equivalent to the one its search meets).
public enum PointGeometryUnion {
    public static func union(_ pointGeom: Geometry, _ otherGeom: Geometry) -> Geometry {
        var locater = PointLocator()
        var exterior = CxxTree<Coordinate, Void> { $0 < $1 }
        for i in 0..<pointGeom.getNumGeometries() {
            let point = pointGeom.getGeometryN(i) as! Point
            guard let coord = point.getCoordinate() else { continue }
            if locater.locate(coord, otherGeom) == Location.exterior { exterior.insert(coord, ()) }
        }
        let exteriorCoords = exterior.inOrder().map { exterior.nodes[$0].key }
        if exteriorCoords.isEmpty { return otherGeom.copy() }
        let factory = otherGeom.factory
        let ptComp: Geometry = exteriorCoords.count == 1
            ? factory.createPoint(exteriorCoords[0]) : factory.createMultiPointFromCoords(exteriorCoords)
        return GeometryCombiner.combine(ptComp, otherGeom)
    }
}
