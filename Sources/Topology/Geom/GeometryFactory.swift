/// Makes geometries of one precision model: JTS's `GeometryFactory` (no
/// SRID, no coordinate sequence factory: coordinates are arrays).
public final class GeometryFactory: Sendable {
    public let precisionModel: PrecisionModel

    public init(precisionModel: PrecisionModel = .floating) {
        self.precisionModel = precisionModel
    }

    /// The factory of floating precision.
    public static let `default` = GeometryFactory()

    public func createPoint() -> Point { Point([], factory: self) }
    public func createPoint(_ c: Coordinate?) -> Point { Point(c.map { [$0] } ?? [], factory: self) }
    public func createPoint(_ coordinates: [Coordinate]) -> Point { Point(coordinates, factory: self) }

    public func createLineString(_ points: [Coordinate] = []) -> LineString { LineString(points, factory: self) }
    public func createLinearRing(_ points: [Coordinate] = []) -> LinearRing { LinearRing(points, factory: self) }

    public func createPolygon(_ shell: LinearRing? = nil, _ holes: [LinearRing] = []) -> Polygon {
        Polygon(shell: shell, holes: holes, factory: self)
    }

    public func createPolygon(_ shell: [Coordinate]) -> Polygon { createPolygon(createLinearRing(shell)) }

    public func createMultiPoint(_ points: [Point] = []) -> MultiPoint { MultiPoint(points, factory: self) }

    public func createMultiPointFromCoords(_ coordinates: [Coordinate]) -> MultiPoint {
        createMultiPoint(coordinates.map { createPoint($0) })
    }

    public func createMultiLineString(_ lines: [LineString] = []) -> MultiLineString { MultiLineString(lines, factory: self) }
    public func createMultiPolygon(_ polygons: [Polygon] = []) -> MultiPolygon { MultiPolygon(polygons, factory: self) }
    public func createGeometryCollection(_ geometries: [Geometry] = []) -> GeometryCollection {
        GeometryCollection(geometries, factory: self)
    }

    /// The geometry of an envelope, as GEOS 3.13 makes it: an empty point, a
    /// point, else a rectangle counter-clockwise from its lower left corner,
    /// flat when the envelope is (JTS 1.20 gives a line for a flat envelope,
    /// and its rectangle is clockwise). An envelope with a NaN side makes a
    /// ring that is not closed, which GEOS refuses: reported as the
    /// orientation test reports GEOS's exceptions (`NonFinite`).
    public func toGeometry(_ e: Envelope) -> Geometry {
        if e.isNull { return createPoint() }
        if e.minX == e.maxX && e.minY == e.maxY { return createPoint(Coordinate(e.minX, e.minY)) }
        guard let ring = try? createLinearRingChecked([
            Coordinate(e.minX, e.minY), Coordinate(e.maxX, e.minY), Coordinate(e.maxX, e.maxY),
            Coordinate(e.minX, e.maxY), Coordinate(e.minX, e.minY),
        ]) else {
            NonFinite.raise()
            return createPolygon()
        }
        return createPolygon(ring)
    }

    /// The smallest geometry type that holds them all, as JTS's
    /// `buildGeometry`: one geometry as itself, several of one type as its
    /// multi-geometry, else a collection.
    public func buildGeometry(_ list: [Geometry]) -> Geometry {
        guard let first = list.first else { return createGeometryCollection() }
        let firstClass = type(of: first)
        let isHeterogeneous = list.contains { type(of: $0) != firstClass }
        let hasCollection = list.contains { $0 is GeometryCollection }
        if isHeterogeneous || hasCollection { return createGeometryCollection(list) }
        if list.count > 1 {
            if first is Polygon { return createMultiPolygon(list.map { $0 as! Polygon }) }
            if first is LineString { return createMultiLineString(list.map { $0 as! LineString }) }
            if first is Point { return createMultiPoint(list.map { $0 as! Point }) }
            preconditionFailure("Unhandled class: \(firstClass)")
        }
        return first
    }

    /// An empty geometry of a dimension (-1 for a collection).
    public func createEmpty(_ dimension: Int) -> Geometry {
        switch dimension {
        case -1: return createGeometryCollection()
        case 0: return createPoint()
        case 1: return createLineString()
        case 2: return createPolygon()
        default: preconditionFailure("Invalid dimension: \(dimension)")
        }
    }

    /// A copy of a geometry made by this factory.
    public func createGeometry(_ g: Geometry) -> Geometry {
        switch g {
        case let p as Point: return createPoint(p.coordinates)
        case let r as LinearRing: return createLinearRing(r.points)
        case let l as LineString: return createLineString(l.points)
        case let p as Polygon:
            return createPolygon(createLinearRing(p.shell.points), p.holes.map { createLinearRing($0.points) })
        case let m as MultiPoint: return createMultiPoint(m.geometries.map { createGeometry($0) as! Point })
        case let m as MultiLineString: return createMultiLineString(m.geometries.map { createGeometry($0) as! LineString })
        case let m as MultiPolygon: return createMultiPolygon(m.geometries.map { createGeometry($0) as! Polygon })
        case let c as GeometryCollection: return createGeometryCollection(c.geometries.map { createGeometry($0) })
        default: preconditionFailure("unknown geometry")
        }
    }
}

extension GeometryFactory {
    /// A ring, or GEOS's error where its constructor refuses the points
    /// (not closed, or too few): JTS's `createLinearRing` traps there, but
    /// rings an operation builds can fail this way on non-finite input,
    /// where GEOS throws.
    public func createLinearRingChecked(_ points: [Coordinate]) throws -> LinearRing {
        if !points.isEmpty {
            if !points[0].equals2D(points[points.count - 1]) {
                throw IllegalArgumentException("Points of LinearRing do not form a closed linestring")
            }
            if points.count < LinearRing.minimumValidRingSize {
                throw IllegalArgumentException("Invalid number of points in LinearRing found \(points.count) - must be 0 or >= 3")
            }
        }
        return createLinearRing(points)
    }
}
