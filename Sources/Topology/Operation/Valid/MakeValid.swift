/// Makes an invalid geometry valid by its linework, keeping every point,
/// line and area of the input: the "linework" method of `GEOSMakeValid`,
/// the GEOS 3.13 default (GEOS's `MakeValid`, from rttopo and PostGIS's
/// `ST_MakeValid`; JTS has only the other, structural method, its
/// `GeometryFixer`).
///
/// Written for this port from the algorithm, on the port's JTS operations
/// (robust OverlayNG through GEOS's heuristic overlay, the polygonizer,
/// `BuildArea`), in GEOS's order of operations:
///
/// - A valid geometry is returned as a copy.
/// - A line is noded by its union with its first point (repeated points
///   dissolved; a line of one point collapses to the point).
/// - A multi-line: each line so, the points and the lines collected.
/// - A polygon or multipolygon: its boundary is noded the same way into cut
///   edges, the points that collapsed in the noding are kept apart, and
///   while an area can be built from the cut edges, it is added to the
///   result by symmetric difference and its boundary taken out of the cut
///   edges. The result is the area, the cut edges left and the collapsed
///   points, the non-empty ones.
/// - A collection: each member so.
/// - Anything else invalid (a point, a ring) fails, as in GEOS.
public enum MakeValid {
    public static func build(_ geom: Geometry) throws -> Geometry {
        if try IsValidOp(geom).getValidationError() == nil { return geom.copy() }
        switch geom {
        case let r as LinearRing: throw UnsupportedOperationException("MakeValid: \(r.getGeometryType())")
        case let l as LineString:
            guard let g = try makeValidLine(l) else { throw IllegalStateException("MakeValid: no result") }
            return g
        case let m as MultiLineString:
            guard let g = try makeValidMultiLine(m) else { throw IllegalStateException("MakeValid: no result") }
            return g
        case is Polygon, is MultiPolygon:
            guard let g = try makeValidPoly(geom) else { throw IllegalStateException("MakeValid: no result") }
            return g
        case let c as GeometryCollection where !(c is MultiPoint):
            return c.factory.createGeometryCollection(try c.geometries.map { try build($0) })
        default:
            throw UnsupportedOperationException("MakeValid: \(geom.getGeometryType())")
        }
    }

    /// The linework noded, by its union with its first point: nil when empty.
    private static func nodeLineWithFirstCoordinate(_ geom: Geometry) throws -> Geometry? {
        if geom.isEmpty() { return nil }
        let line = (geom as? LineString) ?? (geom.getGeometryN(0) as! LineString)
        return try GeometryOverlay.heuristicOverlay(geom, line.getPointN(0), OverlayNG.union)
    }

    private static func makeValidLine(_ line: LineString) throws -> Geometry? { try nodeLineWithFirstCoordinate(line) }

    private static func makeValidMultiLine(_ mls: MultiLineString) throws -> Geometry? {
        var points: [Geometry] = []
        var lines: [Geometry] = []
        for sub in mls.geometries {
            guard let valid = try makeValidLine(sub as! LineString), !valid.isEmpty() else { continue }
            switch valid {
            case is Point: points.append(valid)
            case is LineString: lines.append(valid)
            case let m as MultiLineString: lines.append(contentsOf: m.geometries.map { $0.copy() })
            default: throw UnsupportedOperationException("MakeValid: \(valid.getGeometryType())")
            }
        }
        let f = mls.factory
        let pointsRet: Geometry? = points.isEmpty ? nil : (points.count > 1 ? f.createMultiPoint(points.map { $0 as! Point }) : points[0])
        let linesRet: Geometry? = lines.isEmpty ? nil : (lines.count > 1 ? f.createMultiLineString(lines.map { $0 as! LineString }) : lines[0])
        if let pointsRet, let linesRet { return f.createGeometryCollection([pointsRet, linesRet]) }
        return pointsRet ?? linesRet
    }

    /// The coordinates of a geometry, each once, in the order they first
    /// occur (GEOS's `UniqueCoordinateArrayFilter`), as a multipoint.
    private static func extractUniquePoints(_ geom: Geometry) -> MultiPoint {
        // The seen coordinates in GEOS's `std::set` (libc++'s tree).
        var seen = CxxTree<Coordinate, Void> { $0 < $1 }
        var points: [Point] = []
        for c in geom.getCoordinates() where seen.insert(c, ()).1 { points.append(geom.factory.createPoint(c)) }
        return geom.factory.createMultiPoint(points)
    }

    private static func makeValidPoly(_ geom: Geometry) throws -> Geometry? {
        let bound = geom.getBoundary()
        // The noded boundaries are the first cut edges.
        guard var cutEdges = try nodeLineWithFirstCoordinate(bound) else { return nil }
        // The noding may drop lines collapsing to points: they are kept.
        let pi = extractUniquePoints(bound)
        let po = extractUniquePoints(cutEdges)
        let collapsePoints = try GeometryOverlay.heuristicOverlay(pi, po, OverlayNG.difference)
        let factory = geom.factory
        var area: Geometry = factory.createPolygon()
        // While an area can be built from the edges left, it goes into the
        // result by symmetric difference, its boundary out of the edges.
        while cutEdges.getNumGeometries() > 0 {
            let newArea = try BuildArea.build(cutEdges)
            if newArea.isEmpty() { break }
            let newAreaBound = newArea.getBoundary()
            area = try GeometryOverlay.heuristicOverlay(area, newArea, OverlayNG.symDifference)
            cutEdges = try GeometryOverlay.heuristicOverlay(cutEdges, newAreaBound, OverlayNG.difference)
        }
        let vgeoms = [area, cutEdges, collapsePoints].filter { !$0.isEmpty() }
        if vgeoms.count == 1 { return vgeoms[0] }
        return factory.createGeometryCollection(vgeoms)
    }
}

/// An operation not supported on its input: JTS's `UnsupportedOperationException`.
public struct UnsupportedOperationException: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

extension Geometry {
    /// The geometry made valid by its linework (`GEOSMakeValid`).
    public func makeValid() throws -> Geometry { try NonFinite.scope { try MakeValid.build(self) } }
}
