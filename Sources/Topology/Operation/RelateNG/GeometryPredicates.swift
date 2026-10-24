/// The spatial predicates as `Geometry`'s methods, dispatched as GEOS 3.13
/// does (JTS 1.20 runs its old relate unless told otherwise): RelateNG for
/// all of them, after an envelope test for intersects and touches, and the
/// rectangle's fast path for intersects. They throw where JTS and GEOS
/// fail (a point against an empty collection in the full matrix).
extension Geometry {
    public func intersects(_ g: Geometry) throws -> Bool {
        if !getEnvelopeInternal().intersects(g.getEnvelopeInternal()) { return false }
        if isRectangle() { return RectangleIntersects.intersects(self as! Polygon, g) }
        if g.isRectangle() { return RectangleIntersects.intersects(g as! Polygon, self) }
        return try RelateNG.intersects(self, g)
    }

    public func disjoint(_ g: Geometry) throws -> Bool { try RelateNG.disjoint(self, g) }

    public func touches(_ g: Geometry) throws -> Bool {
        if !getEnvelopeInternal().intersects(g.getEnvelopeInternal()) { return false }
        return try RelateNG.touches(self, g)
    }

    public func contains(_ g: Geometry) throws -> Bool { try RelateNG.contains(self, g) }
    public func within(_ g: Geometry) throws -> Bool { try RelateNG.within(self, g) }
    public func covers(_ g: Geometry) throws -> Bool { try RelateNG.covers(self, g) }
    public func coveredBy(_ g: Geometry) throws -> Bool { try RelateNG.coveredBy(self, g) }
    public func crosses(_ g: Geometry) throws -> Bool { try RelateNG.crosses(self, g) }
    public func overlaps(_ g: Geometry) throws -> Bool { try RelateNG.overlaps(self, g) }
    public func equalsTopo(_ g: Geometry) throws -> Bool { try RelateNG.equalsTopo(self, g) }
    public func relate(_ g: Geometry, _ pattern: String) throws -> Bool { try RelateNG.relate(self, g, pattern) }
    public func relate(_ g: Geometry) throws -> IntersectionMatrix { try RelateNG.relate(self, g) }
}
