/// Prepared lines: intersects by their segments in an index, then by
/// points: JTS's `PreparedLineString` and `PreparedLineStringIntersects`.
final class PreparedLineString: BasicPreparedGeometry {
    @exclusivity(unchecked) private var segIntFinder: FastSegmentSetIntersectionFinder?

    var intersectionFinder: FastSegmentSetIntersectionFinder {
        if let segIntFinder { return segIntFinder }
        let f = FastSegmentSetIntersectionFinder(SegmentStringUtil.extractSegmentStrings(geometry))
        segIntFinder = f
        return f
    }

    override func intersects(_ g: Geometry) throws -> Bool {
        if !envelopesIntersect(g) { return false }
        let lineSegStr = SegmentStringUtil.extractSegmentStrings(g)
        if intersectionFinder.intersects(lineSegStr) { return true }
        // Lines inside an area.
        if g.getDimension() == 2 && isAnyTargetComponentInTest(g) { return true }
        if g.hasDimension(0) { return isAnyTestPointInTarget(g) }
        return false
    }

    private func isAnyTestPointInTarget(_ testGeom: Geometry) -> Bool {
        var locator = PointLocator()
        var coords: [Coordinate] = []
        testGeom.applyComponents { c in
            if c is LineString || c is Point, let p = c.getCoordinate() { coords.append(p) }
        }
        return coords.contains { locator.intersects($0, geometry) }
    }
}
