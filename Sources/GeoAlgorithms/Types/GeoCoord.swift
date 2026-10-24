/// The scalar geometry types of geo-types 0.7.17 for `f64`: `Coord` and `Point`, with the
/// arithmetic operators geo-types defines on them.

/// A two dimensional coordinate, geo-types' `Coord<f64>`. Equality is IEEE equality of both
/// components, as Rust's derived `PartialEq`.
public struct GeoCoord: Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// `Coord::zero()`.
    public static let zero = GeoCoord(x: 0, y: 0)

    /// `Coord::x_y()`.
    public var xY: (Double, Double) { (x, y) }

    public var description: String { "(\(x), \(y))" }

    public static func + (lhs: GeoCoord, rhs: GeoCoord) -> GeoCoord {
        GeoCoord(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: GeoCoord, rhs: GeoCoord) -> GeoCoord {
        GeoCoord(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: GeoCoord, rhs: Double) -> GeoCoord {
        GeoCoord(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func / (lhs: GeoCoord, rhs: Double) -> GeoCoord {
        GeoCoord(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    public static prefix func - (value: GeoCoord) -> GeoCoord {
        GeoCoord(x: -value.x, y: -value.y)
    }
}

/// A single point, geo-types' `Point<f64>`: a wrapper around one coordinate.
public struct GeoPoint: Hashable, Sendable, CustomStringConvertible {
    public var coord: GeoCoord

    public init(_ coord: GeoCoord) {
        self.coord = coord
    }

    public init(x: Double, y: Double) {
        self.coord = GeoCoord(x: x, y: y)
    }

    public var x: Double {
        get { coord.x }
        set { coord.x = newValue }
    }

    public var y: Double {
        get { coord.y }
        set { coord.y = newValue }
    }

    public var description: String { "Point\(coord)" }

    /// `Point::dot`.
    public func dot(_ other: GeoPoint) -> Double {
        x * other.x + y * other.y
    }

    /// `Point::cross_prod`.
    public func crossProd(_ pointB: GeoPoint, _ pointC: GeoPoint) -> Double {
        (pointB.x - x) * (pointC.y - y) - (pointB.y - y) * (pointC.x - x)
    }

    public static func + (lhs: GeoPoint, rhs: GeoPoint) -> GeoPoint {
        GeoPoint(lhs.coord + rhs.coord)
    }

    public static func - (lhs: GeoPoint, rhs: GeoPoint) -> GeoPoint {
        GeoPoint(lhs.coord - rhs.coord)
    }

    public static func * (lhs: GeoPoint, rhs: Double) -> GeoPoint {
        GeoPoint(lhs.coord * rhs)
    }

    public static func / (lhs: GeoPoint, rhs: Double) -> GeoPoint {
        GeoPoint(lhs.coord / rhs)
    }
}

/// A collection of points, geo-types' `MultiPoint<f64>`.
public struct GeoMultiPoint: Hashable, Sendable {
    public var points: [GeoPoint]

    public init(_ points: [GeoPoint]) {
        self.points = points
    }
}
