/// The interior point of points: the one nearest the centroid.
///
/// As GEOS 3.13 has it where JTS 1.20 differs, which only non-finite
/// coordinates show: a geometry with no centroid has no interior point, and
/// where no point is nearer than infinity (every distance NaN) the interior
/// point is GEOS's default coordinate, (0, 0).
struct InteriorPointPoint {
    let centroid: Coordinate
    var minDistance = Double.infinity
    var interiorPoint: Coordinate?

    init(_ g: Geometry) {
        guard let c = g.getCentroid().getCoordinate() else {
            centroid = Coordinate(0, 0)
            return
        }
        centroid = c
        interiorPoint = Coordinate(0, 0)
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
