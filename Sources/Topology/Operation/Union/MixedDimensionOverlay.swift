/// The overlay of collections of mixed dimensions, which OverlayNG does not
/// take, as GEOS 3.13 computes it (JTS refuses such collections): each
/// input's points, lines and polygons unioned apart, the overlay done
/// dimension by dimension, the pieces unioned by dimension again, and the
/// lower dimensions cut away where a higher one covers them. Not in JTS:
/// written from GEOS's documented behaviour, checked against its results.
struct MixedDimensionOverlay {
    let factory: GeometryFactory
    let points: Geometry
    let lines: Geometry
    let polygons: Geometry

    /// The non-empty points, lines and polygons of a geometry, by dimension,
    /// each unioned.
    init(_ g: Geometry) throws { try self.init(parts: [g], factory: g.factory) }

    private init(parts: [Geometry], factory: GeometryFactory) throws {
        self.factory = factory
        var pts: [Point] = [], lns: [LineString] = [], polys: [Polygon] = []
        func read(_ g: Geometry) throws {
            if let gc = g as? GeometryCollection {
                for c in gc.geometries { try read(c) }
                return
            }
            if g.isEmpty() { return }
            switch g {
            case let p as Point: pts.append(p)
            case is LinearRing: throw IllegalArgumentException("cannot process unexpected collection")
            case let l as LineString: lns.append(l)
            case let p as Polygon: polys.append(p)
            default: throw IllegalArgumentException("cannot process unexpected collection")
            }
        }
        for p in parts { try read(p) }
        points = try OverlayNGRobust.union(factory.createMultiPoint(pts))
        lines = try OverlayNGRobust.union(factory.createMultiLineString(lns))
        polygons = try OverlayNGRobust.union(factory.createMultiPolygon(polys))
        if !points.isDimensionStrict(0) { throw IllegalArgumentException("union of points not puntal") }
        if !lines.isDimensionStrict(1) { throw IllegalArgumentException("union of lines not lineal") }
        if !polygons.isDimensionStrict(2) { throw IllegalArgumentException("union of polygons not polygonal") }
    }

    private static func ov(_ a: Geometry, _ b: Geometry, _ opCode: Int) throws -> Geometry {
        try OverlayNGRobust.overlay(a, b, opCode)
    }

    func overlay(_ other: MixedDimensionOverlay, _ opCode: Int) throws -> Geometry {
        let o = other
        let pieces: [Geometry]
        switch opCode {
        case OverlayNG.union:
            pieces = [try Self.ov(o.polygons, polygons, opCode), try Self.ov(o.lines, lines, opCode),
                      try Self.ov(o.points, points, opCode)]
        case OverlayNG.intersection:
            // Every dimension of this against every dimension of the other.
            var p: [Geometry] = []
            for m in [polygons, lines, points] {
                for t in [o.polygons, o.lines, o.points] { p.append(try Self.ov(m, t, opCode)) }
            }
            pieces = p
        case OverlayNG.difference:
            let polyDiff = try Self.ov(polygons, o.polygons, opCode)
            let lineDiffPoly = try Self.ov(lines, o.polygons, opCode)
            let ptDiffPoly = try Self.ov(points, o.polygons, opCode)
            let lineDiff = try Self.ov(lineDiffPoly, o.lines, opCode)
            let ptDiffLine = try Self.ov(ptDiffPoly, lineDiff, opCode)
            pieces = [polyDiff, lineDiff, try Self.ov(ptDiffLine, o.points, opCode)]
        default:
            // GEOS's symmetric difference: of the polygons, and the
            // differences of the lines and of the points.
            pieces = [try Self.ov(polygons, o.polygons, OverlayNG.symDifference),
                      try Self.ov(lines, o.lines, OverlayNG.difference),
                      try Self.ov(points, o.points, OverlayNG.difference)]
        }
        return try MixedDimensionOverlay(parts: pieces, factory: factory).unaryUnion()
    }

    /// The parts by dimension, each with the higher dimensions cut away.
    private func unaryUnion() throws -> Geometry {
        let ptsLessLines = try Self.ov(points, lines, OverlayNG.difference)
        let ptsLessPolysLines = try Self.ov(ptsLessLines, polygons, OverlayNG.difference)
        let linesLessPolys = try Self.ov(lines, polygons, OverlayNG.difference)
        var geoms: [Geometry] = []
        func toVector(_ g: Geometry) {
            if g.isEmpty() { return }
            if let gc = g as? GeometryCollection {
                for c in gc.geometries { toVector(c) }
                return
            }
            if g is Point || (g is LineString && !(g is LinearRing)) || g is Polygon { geoms.append(g) }
        }
        toVector(ptsLessPolysLines)
        toVector(linesLessPolys)
        toVector(polygons)
        return factory.buildGeometry(geoms)
    }
}
