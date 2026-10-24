/// geo-types' two-coordinate shapes for `f64`: `Line`, `Rect` (which orders its corners on
/// construction) and `Triangle`.

/// A line segment from `start` to `end`, geo-types' `Line<f64>`.
public struct GeoLine: Hashable, Sendable {
    public var start: GeoCoord
    public var end: GeoCoord

    public init(_ start: GeoCoord, _ end: GeoCoord) {
        self.start = start
        self.end = end
    }

    public init(start: GeoCoord, end: GeoCoord) {
        self.start = start
        self.end = end
    }

    /// `Line::delta`: `end - start`.
    public var delta: GeoCoord { end - start }
    public var dx: Double { delta.x }
    public var dy: Double { delta.y }
    public var slope: Double { dy / dx }

    /// `Line::determinant`: `start.x * end.y - start.y * end.x`.
    public var determinant: Double { start.x * end.y - start.y * end.x }

    public var startPoint: GeoPoint { GeoPoint(start) }
    public var endPoint: GeoPoint { GeoPoint(end) }
}

/// An axis-aligned rectangle, geo-types' `Rect<f64>`. `init` orders the corners so that
/// `min <= max` on each axis, as `Rect::new` does.
public struct GeoRect: Hashable, Sendable {
    public private(set) var min: GeoCoord
    public private(set) var max: GeoCoord

    public init(_ c1: GeoCoord, _ c2: GeoCoord) {
        let (minX, maxX) = c1.x < c2.x ? (c1.x, c2.x) : (c2.x, c1.x)
        let (minY, maxY) = c1.y < c2.y ? (c1.y, c2.y) : (c2.y, c1.y)
        self.min = GeoCoord(x: minX, y: minY)
        self.max = GeoCoord(x: maxX, y: maxY)
    }

    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }

    /// `Rect::center`.
    public var center: GeoCoord {
        GeoCoord(x: (max.x + min.x) / 2, y: (max.y + min.y) / 2)
    }

    /// `Rect::to_polygon`, starting at the lower right corner as geo-types does.
    public func toPolygon() -> GeoPolygon {
        GeoPolygon(GeoLineString([
            GeoCoord(x: max.x, y: min.y),
            GeoCoord(x: max.x, y: max.y),
            GeoCoord(x: min.x, y: max.y),
            GeoCoord(x: min.x, y: min.y),
            GeoCoord(x: max.x, y: min.y),
        ]), [])
    }

    /// `Rect::to_lines`.
    public func toLines() -> [GeoLine] {
        [
            GeoLine(GeoCoord(x: max.x, y: min.y), GeoCoord(x: max.x, y: max.y)),
            GeoLine(GeoCoord(x: max.x, y: max.y), GeoCoord(x: min.x, y: max.y)),
            GeoLine(GeoCoord(x: min.x, y: max.y), GeoCoord(x: min.x, y: min.y)),
            GeoLine(GeoCoord(x: min.x, y: min.y), GeoCoord(x: max.x, y: min.y)),
        ]
    }
}

/// A triangle of three coordinates, geo-types' `Triangle<f64>`.
public struct GeoTriangle: Hashable, Sendable {
    public var v0: GeoCoord
    public var v1: GeoCoord
    public var v2: GeoCoord

    public init(_ v0: GeoCoord, _ v1: GeoCoord, _ v2: GeoCoord) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
    }

    /// `Triangle::to_array`.
    public var vertices: [GeoCoord] { [v0, v1, v2] }

    /// `Triangle::to_lines`.
    public func toLines() -> [GeoLine] {
        [GeoLine(v0, v1), GeoLine(v1, v2), GeoLine(v2, v0)]
    }

    /// `Triangle::to_polygon`.
    public func toPolygon() -> GeoPolygon {
        GeoPolygon(GeoLineString([v0, v1, v2, v0]), [])
    }
}
