/// geo-types' `LineString<f64>` and `MultiLineString<f64>`: an ordered, contiguous array of
/// coordinates, with the segment views (`lines`, `triangles`) and the ring closing geo-types has.

/// An ordered series of coordinates. A closed line string (first equals last) is a ring.
public struct GeoLineString: Hashable, Sendable {
    public var coords: [GeoCoord]

    /// `LineString::new`: takes the coordinates as they are, without closing them.
    public init(_ coords: [GeoCoord]) {
        self.coords = coords
    }

    /// `LineString::from(Vec<Point>)`.
    public init(points: [GeoPoint]) {
        self.coords = points.map(\.coord)
    }

    /// `LineString::empty()`.
    public static let empty = GeoLineString([])

    public var count: Int { coords.count }
    public var isEmpty: Bool { coords.isEmpty }

    public subscript(index: Int) -> GeoCoord {
        get { coords[index] }
        set { coords[index] = newValue }
    }

    /// `LineString::points`.
    public var points: [GeoPoint] { coords.map(GeoPoint.init) }

    /// `LineString::lines`: one line per pair of consecutive coordinates.
    public var lines: [GeoLine] {
        guard coords.count >= 2 else { return [] }
        var result: [GeoLine] = []
        result.reserveCapacity(coords.count - 1)
        for i in 0..<(coords.count - 1) {
            result.append(GeoLine(coords[i], coords[i + 1]))
        }
        return result
    }

    /// `LineString::triangles`: one triangle per three consecutive coordinates.
    public var triangles: [GeoTriangle] {
        guard coords.count >= 3 else { return [] }
        var result: [GeoTriangle] = []
        result.reserveCapacity(coords.count - 2)
        for i in 0..<(coords.count - 2) {
            result.append(GeoTriangle(coords[i], coords[i + 1], coords[i + 2]))
        }
        return result
    }

    /// `LineString::is_closed`: the first and last coordinates are equal. An empty line string
    /// is closed, since `first() == last()` compares `None` with `None`.
    public var isClosed: Bool {
        coords.first == coords.last
    }

    /// `LineString::close`: appends the first coordinate unless the line string is closed.
    public mutating func close() {
        if !isClosed {
            coords.append(coords[0])
        }
    }
}

/// A collection of line strings, geo-types' `MultiLineString<f64>`.
public struct GeoMultiLineString: Hashable, Sendable {
    public var lineStrings: [GeoLineString]

    public init(_ lineStrings: [GeoLineString]) {
        self.lineStrings = lineStrings
    }
}
