/// The interior point of lines: the inner vertex nearest the centroid, or
/// the endpoint nearest it when no line has an inner vertex.
struct InteriorPointLine {
    let centroid: Coordinate
    var minDistance = Double.greatestFiniteMagnitude
    var interiorPoint: Coordinate?

    init(_ g: Geometry) {
        centroid = g.getCentroid().getCoordinate()!
        addInterior(g)
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
        if dist < minDistance {
            interiorPoint = point
            minDistance = dist
        }
    }
}
