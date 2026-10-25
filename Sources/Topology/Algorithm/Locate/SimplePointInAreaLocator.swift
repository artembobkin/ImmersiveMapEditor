/// Locates points in an areal geometry by testing every ring, with no
/// index: JTS's `SimplePointInAreaLocator`. Polygons of a collection are
/// tested in turn, the first location that is not exterior returned.
public final class SimplePointInAreaLocator: PointOnGeometryLocator {
    private let geom: Geometry

    public init(_ geom: Geometry) { self.geom = geom }

    public func locate(_ p: Coordinate) -> Int { SimplePointInAreaLocator.locate(p, geom) }

    public static func locate(_ p: Coordinate, _ geom: Geometry) -> Int {
        if geom.isEmpty() { return Location.exterior }
        if !geom.getEnvelopeInternal().intersects(p) { return Location.exterior }
        return locateInGeometry(p, geom)
    }

    public static func isContained(_ p: Coordinate, _ geom: Geometry) -> Bool {
        Location.exterior != locate(p, geom)
    }

    private static func locateInGeometry(_ p: Coordinate, _ geom: Geometry) -> Int {
        if let poly = geom as? Polygon { return locatePointInPolygon(p, poly) }
        if geom is GeometryCollection {
            var loc = Location.exterior
            var found = false
            // GeometryCollectionIterator: the tree of geometries in pre-order.
            geom.applyGeometries { g2 in
                if found || g2 === geom { return }
                let l = g2 is GeometryCollection ? Location.exterior : locateInGeometry(p, g2)
                if l != Location.exterior {
                    loc = l
                    found = true
                }
            }
            return loc
        }
        return Location.exterior
    }

    public static func locatePointInPolygon(_ p: Coordinate, _ poly: Polygon) -> Int {
        if poly.isEmpty() { return Location.exterior }
        let shellLoc = locatePointInRing(p, poly.shell)
        if shellLoc != Location.interior { return shellLoc }
        for hole in poly.holes {
            let holeLoc = locatePointInRing(p, hole)
            if holeLoc == Location.boundary { return Location.boundary }
            if holeLoc == Location.interior { return Location.exterior }
        }
        return Location.interior
    }

    public static func containsPointInPolygon(_ p: Coordinate, _ poly: Polygon) -> Bool {
        Location.exterior != locatePointInPolygon(p, poly)
    }

    private static func locatePointInRing(_ p: Coordinate, _ ring: LinearRing) -> Int {
        if !ring.getEnvelopeInternal().intersects(p) { return Location.exterior }
        return PointLocation.locateInRing(p, ring.points)
    }
}
