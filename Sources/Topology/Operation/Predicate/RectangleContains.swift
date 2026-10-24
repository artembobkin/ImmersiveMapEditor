/// Whether a rectangle contains a geometry, faster than in general: the
/// envelope inside the rectangle's and the geometry not lying wholly in its
/// boundary: JTS's `RectangleContains`.
public enum RectangleContains {
    public static func contains(_ rectangle: Polygon, _ geom: Geometry) -> Bool {
        let rectEnv = rectangle.getEnvelopeInternal()
        if !rectEnv.contains(geom.getEnvelopeInternal()) { return false }
        if isContainedInBoundary(rectEnv, geom) { return false }
        return true
    }

    private static func isContainedInBoundary(_ rectEnv: Envelope, _ geom: Geometry) -> Bool {
        // A polygon inside the rectangle has its interior inside it.
        if geom is Polygon { return false }
        if let p = geom as? Point { return isPointContainedInBoundary(rectEnv, p.getCoordinate()!) }
        if let l = geom as? LineString { return isLineStringContainedInBoundary(rectEnv, l) }
        for i in 0..<geom.getNumGeometries() where !isContainedInBoundary(rectEnv, geom.getGeometryN(i)) { return false }
        return true
    }

    private static func isPointContainedInBoundary(_ rectEnv: Envelope, _ pt: Coordinate) -> Bool {
        pt.x == rectEnv.minX || pt.x == rectEnv.maxX || pt.y == rectEnv.minY || pt.y == rectEnv.maxY
    }

    private static func isLineStringContainedInBoundary(_ rectEnv: Envelope, _ line: LineString) -> Bool {
        let seq = line.points
        for i in stride(from: 0, to: seq.count - 1, by: 1) where !isLineSegmentContainedInBoundary(rectEnv, seq[i], seq[i + 1]) {
            return false
        }
        return true
    }

    private static func isLineSegmentContainedInBoundary(_ rectEnv: Envelope, _ p0: Coordinate, _ p1: Coordinate) -> Bool {
        if p0 == p1 { return isPointContainedInBoundary(rectEnv, p0) }
        if p0.x == p1.x {
            if p0.x == rectEnv.minX || p0.x == rectEnv.maxX { return true }
        } else if p0.y == p1.y {
            if p0.y == rectEnv.minY || p0.y == rectEnv.maxY { return true }
        }
        return false
    }
}
