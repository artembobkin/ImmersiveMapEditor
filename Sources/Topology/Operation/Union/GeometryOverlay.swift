/// The overlays of `Geometry` (intersection, union, difference, symmetric
/// difference, unary union) as GEOS 3.13 runs them, which differs from JTS
/// 1.20's `GeometryOverlay`:
///
/// - The overlay is robust OverlayNG (JTS's default is the old overlay).
/// - Empty inputs are not shortcut: OverlayNG's own empty results apply,
///   except that a union of inputs with disjoint envelopes (an empty one
///   included) is the inputs' members put together, not overlaid.
/// - Collections are not refused: a collection of mixed dimensions is
///   overlaid by dimension (`MixedDimensionOverlay`).
/// - The unary union is `UnaryUnionOp` with GEOS's classic strategy.
public enum GeometryOverlay {
    public static func intersection(_ a: Geometry, _ b: Geometry) throws -> Geometry {
        try heuristicOverlay(a, b, OverlayNG.intersection)
    }

    public static func union(_ a: Geometry, _ b: Geometry) throws -> Geometry {
        if !a.getEnvelopeInternal().intersects(b.getEnvelopeInternal()) { return combineMembers(a, b) }
        return try heuristicOverlay(a, b, OverlayNG.union)
    }

    public static func difference(_ a: Geometry, _ b: Geometry) throws -> Geometry {
        try heuristicOverlay(a, b, OverlayNG.difference)
    }

    public static func symDifference(_ a: Geometry, _ b: Geometry) throws -> Geometry {
        if !a.getEnvelopeInternal().intersects(b.getEnvelopeInternal()) && !(a.isEmpty() && b.isEmpty()) {
            return combineMembers(a, b)
        }
        return try heuristicOverlay(a, b, OverlayNG.symDifference)
    }

    public static func union(_ a: Geometry) throws -> Geometry { try UnaryUnionOp.union(a) }

    /// The members of both (a collection's members, else the geometry), as
    /// the most specific geometry.
    private static func combineMembers(_ a: Geometry, _ b: Geometry) -> Geometry {
        var v: [Geometry] = []
        for g in [a, b] {
            if let gc = g as? GeometryCollection { v.append(contentsOf: gc.geometries.map { $0.copy() }) } else { v.append(g.copy()) }
        }
        return a.factory.buildGeometry(v)
    }

    /// Robust OverlayNG, or the overlay by dimension when an input is a
    /// non-empty collection of mixed dimensions.
    static func heuristicOverlay(_ g0: Geometry, _ g1: Geometry, _ opCode: Int) throws -> Geometry {
        if (g0.isMixedDimension && !g0.isEmpty()) || (g1.isMixedDimension && !g1.isEmpty()) {
            let s0 = try MixedDimensionOverlay(g0), s1 = try MixedDimensionOverlay(g1)
            return try s0.overlay(s1, opCode)
        }
        return try OverlayNGRobust.overlay(g0, g1, opCode)
    }
}

extension Geometry {
    /// Whether the atomic parts of the geometry (empty ones included) are of
    /// more than one dimension.
    public var isMixedDimension: Bool {
        var baseDim: Int?
        func mixed(_ g: Geometry) -> Bool {
            if let gc = g as? GeometryCollection { return gc.geometries.contains { mixed($0) } }
            guard let d = baseDim else {
                baseDim = g.getDimension()
                return false
            }
            return d != g.getDimension()
        }
        return mixed(self)
    }

    /// Whether every member is of the dimension (true for an empty
    /// collection): GEOS's strict dimension test.
    func isDimensionStrict(_ d: Int) -> Bool {
        switch self {
        case is MultiPoint: return d == 0
        case is MultiLineString: return d == 1
        case is MultiPolygon: return d == 2
        case let gc as GeometryCollection: return gc.geometries.allSatisfy { $0.getDimension() == d }
        default: return d == getDimension()
        }
    }
}

extension Geometry {
    /// The overlays as `Geometry`'s methods in JTS, run as GEOS 3.13 runs
    /// them (`GeometryOverlay`). They throw where GEOS fails.
    public func intersection(_ other: Geometry) throws -> Geometry { try NonFinite.scope { try GeometryOverlay.intersection(self, other) } }
    public func union(_ other: Geometry) throws -> Geometry { try NonFinite.scope { try GeometryOverlay.union(self, other) } }
    public func difference(_ other: Geometry) throws -> Geometry { try NonFinite.scope { try GeometryOverlay.difference(self, other) } }
    public func symDifference(_ other: Geometry) throws -> Geometry { try NonFinite.scope { try GeometryOverlay.symDifference(self, other) } }
    public func union() throws -> Geometry { try NonFinite.scope { try GeometryOverlay.union(self) } }
}
