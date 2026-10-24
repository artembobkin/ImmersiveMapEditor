/// The interior point of points: the one nearest the centroid.
struct InteriorPointPoint {
    let centroid: Coordinate
    var minDistance = Double.greatestFiniteMagnitude
    var interiorPoint: Coordinate?

    init(_ g: Geometry) {
        centroid = g.getCentroid().getCoordinate()!
        add(g)
    }

    mutating func add(_ geom: Geometry) {
        if geom.isEmpty() { return }
        if geom is Point {
            add(geom.getCoordinate()!)
        } else if let gc = geom as? GeometryCollection {
            for g in gc.geometries { add(g) }
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
