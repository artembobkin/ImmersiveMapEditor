/// geom's operations backed by geo: point in polygon, area, RDP
/// simplification of points, a polyline's winding and closest point.

import GeoAlgorithms

extension Polygon {
    /// geom's `to_geo`: the rings as line strings, closed by geo's `Polygon::new`.
    func toGeo() -> GeoPolygon {
        let exterior = GeoLineString(rings[0].points.map { GeoCoord(x: $0.x, y: $0.y) })
        let interiors = rings.dropFirst().map { GeoLineString($0.points.map { GeoCoord(x: $0.x, y: $0.y) }) }
        return GeoPolygon(exterior, Array(interiors))
    }

    /// Does the polygon contain the point in its interior?
    public func containsPt(_ pt: Pt2D) -> Bool { toGeo().contains(GeoPoint(GeoCoord(x: pt.x, y: pt.y))) }

    /// Unsigned, since polygons come in both orientations.
    public func area() -> Double { toGeo().unsignedArea }
}

extension Pt2D {
    /// Ramer-Douglas-Peucker over the points, then adjacent duplicates removed.
    public static func simplifyRDP(_ pts: [Pt2D], _ epsilon: Double) -> [Pt2D] {
        let ls = GeoLineString(pts.map { GeoCoord(x: $0.x, y: $0.y) })
        var result = ls.simplify(epsilon).coords.map { Pt2D($0.x, $0.y) }
        result.dedup()
        return result
    }
}

extension PolyLine {
    /// False does not mean counter-clockwise: it might be neither.
    public func isClockwise() -> Bool {
        GeoLineString(points.map { GeoCoord(x: $0.x, y: $0.y) }).isCW
    }
}
