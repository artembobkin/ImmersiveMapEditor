/// A prepared geometry of any kind: its predicates by a prepared RelateNG,
/// made at the first one, as GEOS 3.13 has them (JTS: by the geometry's
/// own predicates). The kinds with fast paths override some of them.
public class BasicPreparedGeometry: PreparedGeometry {
    public let geometry: Geometry
    /// A coordinate of each line and point component.
    let representativePts: [Coordinate]
    @exclusivity(unchecked) private var relateNG: RelateNG?

    init(_ geom: Geometry) {
        geometry = geom
        var pts: [Coordinate] = []
        geom.applyComponents { c in
            if c is LineString || c is Point, let p = c.getCoordinate() { pts.append(p) }
        }
        representativePts = pts
    }

    var prepared: RelateNG {
        if let relateNG { return relateNG }
        let r = RelateNG.prepare(geometry)
        relateNG = r
        return r
    }

    /// Whether a point of a component of this geometry is in the test geometry.
    func isAnyTargetComponentInTest(_ testGeom: Geometry) -> Bool {
        var locator = PointLocator()
        return representativePts.contains { locator.intersects($0, testGeom) }
    }

    /// The envelopes meet (a point's coordinate tested alone, as GEOS does).
    func envelopesIntersect(_ g: Geometry) -> Bool {
        if g is Point {
            guard let pt = g.getCoordinate() else { return false }
            return geometry.getEnvelopeInternal().intersects(pt)
        }
        return geometry.getEnvelopeInternal().intersects(g.getEnvelopeInternal())
    }

    func envelopeCovers(_ g: Geometry) -> Bool {
        if g is Point {
            guard let pt = g.getCoordinate() else { return false }
            return geometry.getEnvelopeInternal().covers(pt)
        }
        return geometry.getEnvelopeInternal().covers(g.getEnvelopeInternal())
    }

    public func contains(_ g: Geometry) throws -> Bool { try prepared.contains(g) }
    public func intersects(_ g: Geometry) throws -> Bool { try prepared.intersects(g) }
    public func within(_ g: Geometry) throws -> Bool { try prepared.within(g) }
    public func covers(_ g: Geometry) throws -> Bool { try prepared.covers(g) }
    public func containsProperly(_ g: Geometry) throws -> Bool { try prepared.evaluate(g, "T**FF*FF*") }
}
