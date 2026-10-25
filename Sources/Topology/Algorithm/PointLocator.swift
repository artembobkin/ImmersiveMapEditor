/// The location of a point in any geometry: JTS's `PointLocator`.
public struct PointLocator {
    let boundaryRule: BoundaryNodeRule
    private var isIn = false
    private var numBoundaries = 0

    public init(_ rule: BoundaryNodeRule = .ogcSFS) { boundaryRule = rule }

    public mutating func intersects(_ p: Coordinate, _ geom: Geometry) -> Bool { locate(p, geom) != Location.exterior }

    public mutating func locate(_ p: Coordinate, _ geom: Geometry) -> Int {
        if geom.isEmpty() { return Location.exterior }
        if let l = geom as? LineString { return locateOnLineString(p, l) }
        if let poly = geom as? Polygon { return locateInPolygon(p, poly) }
        isIn = false
        numBoundaries = 0
        computeLocation(p, geom)
        if boundaryRule.isInBoundary(numBoundaries) { return Location.boundary }
        if numBoundaries > 0 || isIn { return Location.interior }
        return Location.exterior
    }

    private mutating func computeLocation(_ p: Coordinate, _ geom: Geometry) {
        if geom.isEmpty() { return }
        if let pt = geom as? Point { updateLocationInfo(locateOnPoint(p, pt)) }
        if let l = geom as? LineString {
            updateLocationInfo(locateOnLineString(p, l))
        } else if let poly = geom as? Polygon {
            updateLocationInfo(locateInPolygon(p, poly))
        } else if let ml = geom as? MultiLineString {
            for l in ml.geometries { updateLocationInfo(locateOnLineString(p, l as! LineString)) }
        } else if let mp = geom as? MultiPolygon {
            for poly in mp.geometries { updateLocationInfo(locateInPolygon(p, poly as! Polygon)) }
        } else if let gc = geom as? GeometryCollection {
            // GEOS 3.13 recurses into the members (JTS iterates the whole
            // tree in pre-order and recurses as well, which counts the
            // members of a nested collection twice).
            for g2 in gc.geometries { computeLocation(p, g2) }
        }
    }

    private mutating func updateLocationInfo(_ loc: Int) {
        if loc == Location.interior { isIn = true }
        if loc == Location.boundary { numBoundaries += 1 }
    }

    private func locateOnPoint(_ p: Coordinate, _ pt: Point) -> Int {
        pt.getCoordinate()!.equals2D(p) ? Location.interior : Location.exterior
    }

    private func locateOnLineString(_ p: Coordinate, _ l: LineString) -> Int {
        if !l.getEnvelopeInternal().intersects(p) { return Location.exterior }
        let seq = l.points
        if p == seq[0] || p == seq[seq.count - 1] {
            let boundaryCount = l.isClosed() ? 2 : 1
            return boundaryRule.isInBoundary(boundaryCount) ? Location.boundary : Location.interior
        }
        if PointLocation.isOnLine(p, seq) { return Location.interior }
        return Location.exterior
    }

    /// As GEOS 3.13: on the ring's line first (`isOnLine`), then inside it
    /// (JTS 1.20: one pass of the ray crossing counter). The location is the
    /// same; a vertex is found before an orientation test meets it.
    private func locateInPolygonRing(_ p: Coordinate, _ ring: LinearRing) -> Int {
        if !ring.getEnvelopeInternal().intersects(p) { return Location.exterior }
        if PointLocation.isOnLine(p, ring.points) { return Location.boundary }
        if PointLocation.isInRing(p, ring.points) { return Location.interior }
        return Location.exterior
    }

    private func locateInPolygon(_ p: Coordinate, _ poly: Polygon) -> Int {
        if poly.isEmpty() { return Location.exterior }
        let shellLoc = locateInPolygonRing(p, poly.shell)
        if shellLoc == Location.exterior { return Location.exterior }
        if shellLoc == Location.boundary { return Location.boundary }
        for hole in poly.holes {
            let holeLoc = locateInPolygonRing(p, hole)
            if holeLoc == Location.interior { return Location.exterior }
            if holeLoc == Location.boundary { return Location.boundary }
        }
        return Location.interior
    }
}
