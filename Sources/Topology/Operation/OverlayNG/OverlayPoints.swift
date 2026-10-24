/// The overlay of two puntal inputs, by set operations on their points
/// (rounded at a fixed precision): JTS's `OverlayPoints`. GEOS keeps the
/// points in an ordered map, so the result's points come out ordered by x,
/// then y (JTS: a hash map's order), the first point of equal ones kept.
enum OverlayPoints {
    static func overlay(_ opCode: Int, _ geom0: Geometry, _ geom1: Geometry, _ pm: PrecisionModel?) -> Geometry {
        let factory = geom0.factory
        let map0 = buildPointMap(geom0, pm), map1 = buildPointMap(geom1, pm)
        func contains(_ map: [(Coordinate, Point)], _ c: Coordinate) -> Bool { find(map, c) != nil }
        var resultList: [Point] = []
        switch opCode {
        case OverlayNG.intersection:
            for (c, p) in map0 where contains(map1, c) { resultList.append(copyPoint(p, pm, factory)) }
        case OverlayNG.union:
            for (_, p) in map0 { resultList.append(copyPoint(p, pm, factory)) }
            for (c, p) in map1 where !contains(map0, c) { resultList.append(copyPoint(p, pm, factory)) }
        case OverlayNG.difference:
            for (c, p) in map0 where !contains(map1, c) { resultList.append(copyPoint(p, pm, factory)) }
        case OverlayNG.symDifference:
            for (c, p) in map0 where !contains(map1, c) { resultList.append(copyPoint(p, pm, factory)) }
            for (c, p) in map1 where !contains(map0, c) { resultList.append(copyPoint(p, pm, factory)) }
        default: break
        }
        if resultList.isEmpty { return OverlayUtil.createEmptyResult(0, factory) }
        return factory.buildGeometry(resultList)
    }

    private static func copyPoint(_ pt: Point, _ pm: PrecisionModel?, _ factory: GeometryFactory) -> Point {
        if OverlayUtil.isFloating(pm) { return pt.copy() as! Point }
        return factory.createPoint(pm!.makePrecise(pt.getCoordinate()!))
    }

    /// The input's points by their rounded coordinates, sorted, the first of
    /// equal ones kept.
    private static func buildPointMap(_ geoms: Geometry, _ pm: PrecisionModel?) -> [(Coordinate, Point)] {
        var map: [(Coordinate, Point)] = []
        geoms.applyComponents { g in
            guard let pt = g as? Point, !pt.isEmpty() else { return }
            let p = roundCoord(pt, pm)
            let i = lowerBound(map, p)
            if i < map.count && map[i].0 == p { return }
            map.insert((p, pt), at: i)
        }
        return map
    }

    private static func lowerBound(_ map: [(Coordinate, Point)], _ c: Coordinate) -> Int {
        var lo = 0, hi = map.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if map[mid].0 < c { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private static func find(_ map: [(Coordinate, Point)], _ c: Coordinate) -> Int? {
        let i = lowerBound(map, c)
        return i < map.count && map[i].0 == c ? i : nil
    }

    static func roundCoord(_ pt: Point, _ pm: PrecisionModel?) -> Coordinate {
        let p = pt.getCoordinate()!
        if OverlayUtil.isFloating(pm) { return p }
        return pm!.makePrecise(p)
    }
}
