/// The interior point of lines: the inner vertex nearest the centroid, or
/// the endpoint nearest it when no line has an inner vertex.
///
/// As GEOS 3.13 has it where JTS 1.20 differs, which only non-finite
/// coordinates show: the first vertex tried is taken whatever its distance
/// (NaN or infinite), and without a centroid the inner vertices are not
/// tried and the endpoints are measured from GEOS's default coordinate,
/// (0, 0).
struct InteriorPointLine {
    let centroid: Coordinate
    var minDistance = Double.infinity
    var interiorPoint: Coordinate?

    init(_ g: Geometry) {
        if let c = g.getCentroid().getCoordinate() {
            centroid = c
            addInterior(g)
        } else {
            centroid = Coordinate(0, 0)
        }
        if interiorPoint == nil { addEndpoints(g) }
    }

    mutating func addInterior(_ geom: Geometry) {
        if geom.isEmpty() { return }
        if let l = geom as? LineString {
            let pts = l.points
            if pts.count > 2 { for i in 1..<(pts.count - 1) { add(pts[i]) } }
        } else if let gc = geom as? GeometryCollection {
            for g in gc.geometries { addInterior(g) }
        }
    }

    mutating func addEndpoints(_ geom: Geometry) {
        if geom.isEmpty() { return }
        if let l = geom as? LineString {
            add(l.points[0])
            add(l.points[l.points.count - 1])
        } else if let gc = geom as? GeometryCollection {
            for g in gc.geometries { addEndpoints(g) }
        }
    }

    mutating func add(_ point: Coordinate) {
        let dist = point.distance(centroid)
        if interiorPoint == nil || dist < minDistance {
            interiorPoint = point
            minDistance = dist
        }
    }
}
