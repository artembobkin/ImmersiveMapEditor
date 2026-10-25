/// Whether a rectangle intersects a geometry, faster than in general: an
/// element whose envelope reaches across the rectangle in x or y, a polygon
/// holding a corner of it, or a segment meeting its ring: JTS's
/// `RectangleIntersects` (with `ShortCircuitedGeometryVisitor`), the last
/// test as GEOS 3.13 makes it: each segment of the rectangle's ring against
/// each of the element's lines (JTS: each segment against the rectangle's
/// diagonals). The answers agree, and these are GEOS's steps.
public enum RectangleIntersects {
    public static func intersects(_ rectangle: Polygon, _ geom: Geometry) -> Bool {
        let rectEnv = rectangle.getEnvelopeInternal()
        if !rectEnv.intersects(geom.getEnvelopeInternal()) { return false }
        if visit(geom, { envelopeIntersects(rectEnv, $0) }) { return true }
        if visit(geom, { containsCorner(rectangle, rectEnv, $0) }) { return true }
        if visit(geom, { rectEnv.intersects($0.getEnvelopeInternal()) && segmentsIntersect(rectangle.shell, $0) }) { return true }
        return false
    }

    /// The atomic elements in order, until one answers true.
    static func visit(_ geom: Geometry, _ f: (Geometry) -> Bool) -> Bool {
        for i in 0..<geom.getNumGeometries() {
            let element = geom.getGeometryN(i)
            if element is GeometryCollection {
                if visit(element, f) { return true }
            } else if f(element) {
                return true
            }
        }
        return false
    }

    /// An element inside the rectangle, or across it in x or y.
    private static func envelopeIntersects(_ rectEnv: Envelope, _ element: Geometry) -> Bool {
        let elementEnv = element.getEnvelopeInternal()
        if !rectEnv.intersects(elementEnv) { return false }
        if rectEnv.contains(elementEnv) { return true }
        if elementEnv.minX >= rectEnv.minX && elementEnv.maxX <= rectEnv.maxX { return true }
        if elementEnv.minY >= rectEnv.minY && elementEnv.maxY <= rectEnv.maxY { return true }
        return false
    }

    /// A polygon holding a corner of the rectangle.
    private static func containsCorner(_ rectangle: Polygon, _ rectEnv: Envelope, _ geom: Geometry) -> Bool {
        guard let poly = geom as? Polygon else { return false }
        let elementEnv = poly.getEnvelopeInternal()
        if !rectEnv.intersects(elementEnv) { return false }
        let rectSeq = rectangle.shell.points
        for i in 0..<4 {
            let rectPt = rectSeq[i]
            if !elementEnv.contains(rectPt) { continue }
            if SimplePointInAreaLocator.containsPointInPolygon(rectPt, poly) { return true }
        }
        return false
    }

    /// A segment of the ring meeting a segment of the element's lines.
    private static func segmentsIntersect(_ ring: LinearRing, _ geom: Geometry) -> Bool {
        var li = RobustLineIntersector()
        let seq0 = ring.points
        for testLine in LinearComponentExtracter.getLines(geom) {
            let seq1 = testLine.points
            for i in stride(from: 1, to: seq0.count, by: 1) {
                for j in stride(from: 1, to: seq1.count, by: 1) {
                    li.computeIntersection(seq0[i - 1], seq0[i], seq1[j - 1], seq1[j])
                    if li.hasIntersection() { return true }
                }
            }
        }
        return false
    }
}
