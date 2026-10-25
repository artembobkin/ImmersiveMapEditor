/// The union of points with a geometry of a higher dimension: the points
/// outside it, sorted and each once, added to it: JTS's
/// `PointGeometryUnion`, as GEOS 3.13 runs it (empty points skipped).
public enum PointGeometryUnion {
    public static func union(_ pointGeom: Geometry, _ otherGeom: Geometry) -> Geometry {
        var locater = PointLocator()
        var exteriorCoords: [Coordinate] = []
        for i in 0..<pointGeom.getNumGeometries() {
            let point = pointGeom.getGeometryN(i) as! Point
            guard let coord = point.getCoordinate() else { continue }
            if locater.locate(coord, otherGeom) == Location.exterior {
                // A sorted set: equal coordinates once, the first kept.
                var lo = 0, hi = exteriorCoords.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if exteriorCoords[mid] < coord { lo = mid + 1 } else { hi = mid }
                }
                if lo == exteriorCoords.count || exteriorCoords[lo] != coord { exteriorCoords.insert(coord, at: lo) }
            }
        }
        if exteriorCoords.isEmpty { return otherGeom.copy() }
        let factory = otherGeom.factory
        let ptComp: Geometry = exteriorCoords.count == 1
            ? factory.createPoint(exteriorCoords[0]) : factory.createMultiPointFromCoords(exteriorCoords)
        return GeometryCombiner.combine(ptComp, otherGeom)
    }
}
