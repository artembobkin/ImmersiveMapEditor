/// The union of the parts of a geometry: the points, the lines and the
/// polygons each unioned (lines and points by a union with an empty
/// geometry, polygons by `CascadedPolygonUnion`), then together: JTS's
/// `UnaryUnionOp`, as GEOS 3.13 runs it. GEOS extracts every point, line
/// and polygon, empty ones included (JTS skips them, and returns an empty
/// geometry of the input's dimension for an empty input), unions with an
/// empty collection (JTS with an empty point), and returns an empty
/// collection when nothing is left.
public final class UnaryUnionOp {
    @exclusivity(unchecked) private var factory: GeometryFactory?
    @exclusivity(unchecked) private var polygons: [Polygon] = []
    @exclusivity(unchecked) private var lines: [LineString] = []
    @exclusivity(unchecked) private var points: [Point] = []
    @exclusivity(unchecked) public var unionFunction = UnionStrategy.classic

    public static func union(_ geom: Geometry) throws -> Geometry { try UnaryUnionOp(geom).union() }

    public init(_ geom: Geometry) { extract(geom) }

    public init(_ geoms: [Geometry], _ factory: GeometryFactory? = nil) {
        self.factory = factory
        for g in geoms { extract(g) }
    }

    private func extract(_ geom: Geometry) {
        if factory == nil { factory = geom.factory }
        geom.applyGeometries { g in
            if let p = g as? Polygon { polygons.append(p) }
        }
        geom.applyGeometries { g in
            if let l = g as? LineString { lines.append(l) }
        }
        geom.applyGeometries { g in
            if let p = g as? Point { points.append(p) }
        }
    }

    /// The union, nil without a factory (no input at all).
    public func union() throws -> Geometry {
        guard let factory else { return GeometryFactory.default.createGeometryCollection() }
        var unionPoints: Geometry?
        if !points.isEmpty { unionPoints = try unionNoOpt(factory.buildGeometry(points)) }
        var unionLines: Geometry?
        if !lines.isEmpty { unionLines = try unionNoOpt(factory.buildGeometry(lines)) }
        var unionPolygons: Geometry?
        if !polygons.isEmpty { unionPolygons = try CascadedPolygonUnion.union(polygons, unionFunction) }
        let unionLA = try unionWithNull(unionLines, unionPolygons)
        var result: Geometry?
        if unionPoints == nil {
            result = unionLA
        } else if unionLA == nil {
            result = unionPoints
        } else {
            result = PointGeometryUnion.union(unionPoints!, unionLA!)
        }
        return result ?? factory.createGeometryCollection()
    }

    private func unionWithNull(_ g0: Geometry?, _ g1: Geometry?) throws -> Geometry? {
        guard let g0 else { return g1 }
        guard let g1 else { return g0 }
        return try GeometryOverlay.union(g0, g1)
    }

    /// The union of a geometry with an empty one, which cleans it.
    private func unionNoOpt(_ g0: Geometry) throws -> Geometry {
        try unionFunction.union(g0, factory!.createGeometryCollection())
    }
}
