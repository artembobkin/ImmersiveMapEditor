/// Prepared points: intersects by locating the points in the other
/// geometry: JTS's `PreparedPoint`.
final class PreparedPoint: BasicPreparedGeometry {
    override func intersects(_ g: Geometry) throws -> Bool {
        if !envelopesIntersect(g) { return false }
        return isAnyTargetComponentInTest(g)
    }
}
