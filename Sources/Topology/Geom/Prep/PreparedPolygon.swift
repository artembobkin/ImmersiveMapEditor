/// Prepared polygons: intersects and contains by fast paths (a rectangle's
/// own tests, then the components' points located in an index, the
/// segments intersected in an index, and the full predicate only when
/// they cannot decide): JTS's `PreparedPolygon` with
/// `PreparedPolygonIntersects` and `PreparedPolygonContains`, the contains
/// as GEOS 3.13 decides it (`containsDecision` below).
final class PreparedPolygon: BasicPreparedGeometry {
    private let isRectangle: Bool
    @exclusivity(unchecked) private var segIntFinder: FastSegmentSetIntersectionFinder?
    @exclusivity(unchecked) private var pointLocator: IndexedPointInAreaLocator?
    @exclusivity(unchecked) private var simpleLocatorGiven = false

    override init(_ geom: Geometry) {
        isRectangle = geom.isRectangle()
        super.init(geom)
    }

    var intersectionFinder: FastSegmentSetIntersectionFinder {
        if let segIntFinder { return segIntFinder }
        let f = FastSegmentSetIntersectionFinder(SegmentStringUtil.extractSegmentStrings(geometry))
        segIntFinder = f
        return f
    }

    /// The point locator of the polygons, as GEOS 3.13 hands it out: the
    /// simple locator the first time, the indexed one after (JTS: always
    /// the indexed one). On invalid polygons (overlapping parts, a hole
    /// outside its shell) the two locate some points differently.
    var locator: PointOnGeometryLocator {
        if !simpleLocatorGiven {
            simpleLocatorGiven = true
            return SimplePointInAreaLocator(geometry)
        }
        if let pointLocator { return pointLocator }
        let l = IndexedPointInAreaLocator(geometry)
        pointLocator = l
        return l
    }

    override func intersects(_ g: Geometry) throws -> Bool {
        if !envelopesIntersect(g) { return false }
        if isRectangle { return RectangleIntersects.intersects(geometry as! Polygon, g) }
        // A point of the test geometry in the polygons.
        if PreparedPolygon.anyComponentLocation(g, locator, { $0 != Location.exterior }) { return true }
        if g.isDimensionStrict(0) { return false }
        if intersectionFinder.intersects(SegmentStringUtil.extractSegmentStrings(g)) { return true }
        // The polygons inside an areal test geometry.
        if g.getDimension() == 2 && isAnyTargetComponentInAreaTest(g) { return true }
        return false
    }

    override func contains(_ g: Geometry) throws -> Bool {
        if !envelopeCovers(g) { return false }
        if isRectangle { return RectangleContains.contains(geometry as! Polygon, g) }
        return try containsDecision(g, requireSomePointInInterior: true) { try RelateNG.contains(self.geometry, $0) }
    }

    override func covers(_ g: Geometry) throws -> Bool {
        if !envelopeCovers(g) { return false }
        if isRectangle { return true }
        return try containsDecision(g, requireSomePointInInterior: false) { try RelateNG.covers(self.geometry, $0) }
    }

    /// Whether the test geometry is inside the interior, touching no boundary.
    override func containsProperly(_ g: Geometry) throws -> Bool {
        if !envelopeCovers(g) { return false }
        if PreparedPolygon.anyComponentLocation(g, locator, { $0 != Location.interior }) { return false }
        if intersectionFinder.intersects(SegmentStringUtil.extractSegmentStrings(g)) { return false }
        if (g is Polygon || g is MultiPolygon) && isAnyTargetComponentInAreaTest(g) { return false }
        return true
    }

    /// GEOS's prepared contains and covers: the outermost location of the
    /// test geometry's components first (JTS: whether all of them are in),
    /// and for points, inside when that location is the interior.
    private func containsDecision(_ geom: Geometry, requireSomePointInInterior: Bool,
                                  _ fullTopologicalPredicate: (Geometry) throws -> Bool) throws -> Bool {
        let outermostLoc = PreparedPolygon.outermostComponentLocation(geom, locator)
        if geom.getDimension() == 0 { return evalPointTestGeom(geom, outermostLoc, requireSomePointInInterior) }
        if outermostLoc == Location.exterior { return false }
        let isPolygonal = geom is Polygon || geom is MultiPolygon
        let properIntersectionImpliesNotContained = isPolygonal || isSingleShell(geometry)
        let intDetector = SegmentIntersectionDetector()
        intDetector.findAllIntersectionTypes = true
        _ = intersectionFinder.intersects(SegmentStringUtil.extractSegmentStrings(geom), intDetector)
        if properIntersectionImpliesNotContained && intDetector.hasProperIntersection { return false }
        // Segments that touch only properly cross out of it.
        if intDetector.hasIntersection && !intDetector.hasNonProperIntersection { return false }
        if intDetector.hasIntersection { return try fullTopologicalPredicate(geom) }
        // A polygon with a piece of this one inside it, as a hole perhaps.
        if isPolygonal && isAnyTargetComponentInAreaTest(geom) { return false }
        return true
    }

    private func evalPointTestGeom(_ geom: Geometry, _ outermostLoc: Int, _ requireSomePointInInterior: Bool) -> Bool {
        if outermostLoc == Location.exterior { return false }
        if !requireSomePointInInterior { return true }
        if outermostLoc == Location.interior { return true }
        // On the boundary: a single point is not contained.
        if geom.getNumPoints() <= 1 { return false }
        return PreparedPolygon.anyComponentLocation(geom, locator) { $0 == Location.interior }
    }

    private func isSingleShell(_ geom: Geometry) -> Bool {
        if geom.getNumGeometries() != 1 { return false }
        return (geom.getGeometryN(0) as! Polygon).holes.isEmpty
    }

    /// Whether a point of a component of this geometry is in the areal test geometry.
    private func isAnyTargetComponentInAreaTest(_ testGeom: Geometry) -> Bool {
        let piaLoc = SimplePointInAreaLocator(testGeom)
        return representativePts.contains { piaLoc.locate($0) != Location.exterior }
    }

    /// The components of a geometry as GEOS's component filter visits them:
    /// a collection, then its members until done; a polygon, then its shell
    /// and its holes until done. Empty ones are skipped.
    static func visitComponents(_ g: Geometry, _ visit: (Geometry) -> Bool) -> Bool {
        if !g.isEmpty() && visit(g) { return true }
        if let gc = g as? GeometryCollection {
            for c in gc.geometries where visitComponents(c, visit) { return true }
        } else if let poly = g as? Polygon {
            if visitComponents(poly.shell, visit) { return true }
            for h in poly.holes where visitComponents(h, visit) { return true }
        }
        return false
    }

    /// Whether the first coordinate of some component has a location.
    static func anyComponentLocation(_ g: Geometry, _ locator: PointOnGeometryLocator, _ test: (Int) -> Bool) -> Bool {
        visitComponents(g) { c in test(locator.locate(c.getCoordinate()!)) }
    }

    /// The outermost location of the components' first coordinates: exterior
    /// if any is, else the boundary once one is (GEOS's
    /// `OutermostLocationFilter`, which keeps a boundary over a later interior).
    static func outermostComponentLocation(_ g: Geometry, _ locator: PointOnGeometryLocator) -> Int {
        var outermost = Location.none
        _ = visitComponents(g) { c in
            let loc = locator.locate(c.getCoordinate()!)
            if outermost == Location.none || outermost == Location.interior {
                outermost = loc
            } else if loc == Location.exterior {
                outermost = loc
                return true
            }
            return false
        }
        return outermost
    }
}
