/// The overlay of two puntal inputs, by set operations on their points
/// (rounded at a fixed precision): JTS's `OverlayPoints`. GEOS keeps the
/// points in an ordered map (`std::map`, here libc++'s tree, `CxxTree`), so
/// the result's points come out ordered by x, then y (JTS: a hash map's
/// order), the first point of equal ones kept.
enum OverlayPoints {
    typealias PointMap = CxxTree<Coordinate, Point>

    static func overlay(_ opCode: Int, _ geom0: Geometry, _ geom1: Geometry, _ pm: PrecisionModel?) -> Geometry {
        let factory = geom0.factory
        let map0 = buildPointMap(geom0, pm), map1 = buildPointMap(geom1, pm)
        var resultList: [Point] = []
        func add(_ map: PointMap, _ keep: (Coordinate) -> Bool) {
            for i in map.inOrder() where keep(map.nodes[i].key) { resultList.append(copyPoint(map.nodes[i].value, pm, factory)) }
        }
        switch opCode {
        case OverlayNG.intersection:
            add(map0) { map1.find($0) != nil }
        case OverlayNG.union:
            add(map0) { _ in true }
            add(map1) { map0.find($0) == nil }
        case OverlayNG.difference:
            add(map0) { map1.find($0) == nil }
        case OverlayNG.symDifference:
            add(map0) { map1.find($0) == nil }
            add(map1) { map0.find($0) == nil }
        default: break
        }
        if resultList.isEmpty { return OverlayUtil.createEmptyResult(0, factory) }
        return factory.buildGeometry(resultList)
    }

    private static func copyPoint(_ pt: Point, _ pm: PrecisionModel?, _ factory: GeometryFactory) -> Point {
        if OverlayUtil.isFloating(pm) { return pt.copy() as! Point }
        return factory.createPoint(pm!.makePrecise(pt.getCoordinate()!))
    }

    /// The input's points by their rounded coordinates, the first of
    /// equivalent ones kept.
    private static func buildPointMap(_ geoms: Geometry, _ pm: PrecisionModel?) -> PointMap {
        var map = PointMap { $0 < $1 }
        geoms.applyComponents { g in
            guard let pt = g as? Point, !pt.isEmpty() else { return }
            map.insert(roundCoord(pt, pm), pt)
        }
        return map
    }

    static func roundCoord(_ pt: Point, _ pm: PrecisionModel?) -> Coordinate {
        let p = pt.getCoordinate()!
        if OverlayUtil.isFloating(pm) { return p }
        return pm!.makePrecise(p)
    }
}
