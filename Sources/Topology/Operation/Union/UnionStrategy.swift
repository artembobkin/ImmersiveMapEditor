/// How two geometries are unioned inside a unary union: JTS's
/// `UnionStrategy`, as the two strategies GEOS 3.13 uses.
public enum UnionStrategy {
    /// GEOS's default (`ClassicUnionStrategy`): the overlay of
    /// `GeometryOverlay.union`'s heuristics, and for two areal inputs that
    /// fail with a `TopologyException` the buffer by zero of both together.
    /// Robust OverlayNG's final failure is not one (`RuntimeError`), so for
    /// floating inputs the buffer is reached only by a topology failure of a
    /// fixed precision overlay, as in GEOS 3.13.
    case classic
    /// Robust overlay alone (GEOS's `SRUnionStrategy`, JTS's `OVERLAY_UNION`
    /// of `OverlayNGRobust`).
    case overlayNGRobust

    func union(_ g0: Geometry, _ g1: Geometry) throws -> Geometry {
        switch self {
        case .overlayNGRobust:
            return try OverlayNGRobust.overlay(g0, g1, OverlayNG.union)
        case .classic:
            do {
                return try GeometryOverlay.heuristicOverlay(g0, g1, OverlayNG.union)
            } catch let e as TopologyException {
                // Union by buffer works for polygons only.
                if g0.getDimension() != 2 || g1.getDimension() != 2 { throw e }
                return try UnionStrategy.unionPolygonsByBuffer(g0, g1)
            }
        }
    }

    /// The buffer by zero of a collection of both.
    private static func unionPolygonsByBuffer(_ g0: Geometry, _ g1: Geometry) throws -> Geometry {
        try BufferOp.bufferOp(g0.factory.createGeometryCollection([g0.copy(), g1.copy()]), 0)
    }
}
