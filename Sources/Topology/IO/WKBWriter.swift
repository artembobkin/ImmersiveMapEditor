/// Writes Well-Known Binary: JTS's `WKBWriter` with two dimensions and
/// little-endian byte order, for the recording mode of `Geometry`, whose
/// geometries are WKB.
///
/// The layout is the one GEOS 3.13's writer gives a two-dimensional
/// geometry in either flavour (ISO and extended agree without Z or M): a
/// byte order byte (1), the type as a `u32` (1 to 7; a linear ring is
/// written as a line string), then the coordinates as `f64`. An empty point
/// is written as the point (NaN, NaN), an empty polygon with no rings, and
/// the members of a collection each as a whole geometry.
public struct WKBWriter {
    public init() {}

    public func write(_ g: Geometry) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(9 + 16 * g.getNumPoints())
        writeGeometry(g, &out)
        return out
    }

    private func writeGeometry(_ g: Geometry, _ out: inout [UInt8]) {
        switch g {
        case let p as Point:
            header(1, &out)
            if let c = p.getCoordinate() {
                put(c, &out)
            } else {
                put(Double.nan, &out)
                put(Double.nan, &out)
            }
        case let l as LineString:
            header(2, &out)
            sequence(l.points, &out)
        case let p as Polygon:
            header(3, &out)
            if p.isEmpty() {
                put(UInt32(0), &out)
                return
            }
            put(UInt32(1 + p.holes.count), &out)
            sequence(p.shell.points, &out)
            for h in p.holes { sequence(h.points, &out) }
        case let c as GeometryCollection:
            let type: UInt32
            switch c {
            case is MultiPoint: type = 4
            case is MultiLineString: type = 5
            case is MultiPolygon: type = 6
            default: type = 7
            }
            header(type, &out)
            put(UInt32(c.geometries.count), &out)
            for m in c.geometries { writeGeometry(m, &out) }
        default:
            preconditionFailure("unknown geometry")
        }
    }

    private func header(_ type: UInt32, _ out: inout [UInt8]) {
        out.append(1)
        put(type, &out)
    }

    private func sequence(_ points: [Coordinate], _ out: inout [UInt8]) {
        put(UInt32(points.count), &out)
        for c in points { put(c, &out) }
    }

    private func put(_ c: Coordinate, _ out: inout [UInt8]) {
        put(c.x, &out)
        put(c.y, &out)
    }

    private func put(_ v: Double, _ out: inout [UInt8]) { put(v.bitPattern, &out) }

    private func put<T: FixedWidthInteger>(_ v: T, _ out: inout [UInt8]) {
        withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
    }
}
