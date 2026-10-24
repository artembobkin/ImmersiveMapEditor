/// geom's `Pt2D` (world space in metres, trimmed to four decimals),
/// `HashablePt2D` (exact equality, for sets and maps) and `LonLat`.

import Foundation

/// A point in world space, metres. `==` is geom's: within `epsilonDist`.
public struct Pt2D: Sendable, CustomStringConvertible {
    public let x: Double
    public let y: Double

    /// geom's `Pt2D::new`: panics on non-finite input, trims both coordinates.
    @inlinable
    public init(_ x: Double, _ y: Double) {
        precondition(x.isFinite && y.isFinite, "Bad Pt2D \(x), \(y)")
        self.x = trimF64(x)
        self.y = trimF64(y)
    }

    public static func zero() -> Pt2D { Pt2D(0.0, 0.0) }

    @inlinable
    public func approxEq(_ other: Pt2D, _ threshold: Distance) -> Bool {
        distTo(other) <= threshold
    }

    public func toGPS(_ b: GPSBounds) -> LonLat { b.convertBackXY(x, y) }

    /// If the distance is negative, this projects in `theta.opposite()`.
    @inlinable
    public func projectAway(_ dist: Distance, _ theta: Angle) -> Pt2D {
        let r = theta.normalizedRadians()
        let s = sin(r)
        let c = cos(r)
        return Pt2D(x + dist.innerMeters * c, y + dist.innerMeters * s)
    }

    @inlinable
    public func rawDistTo(_ to: Pt2D) -> Double {
        let dx = x - to.x
        let dy = y - to.y
        return (dx * dx + dy * dy).squareRoot()
    }

    @inlinable public func distTo(_ to: Pt2D) -> Distance { .meters(rawDistTo(to)) }

    /// Squared distance, for rough comparisons.
    public func fastDist(_ other: Pt2D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }

    /// The angle toward `to`. Y is not inverted.
    @inlinable
    public func angleTo(_ to: Pt2D) -> Angle { .newRads(atan2(to.y - y, to.x - x)) }

    public func offset(_ dx: Double, _ dy: Double) -> Pt2D { Pt2D(x + dx, y + dy) }

    public static func center(_ pts: [Pt2D]) -> Pt2D {
        precondition(!pts.isEmpty, "Can't find center of 0 points")
        var x = 0.0
        var y = 0.0
        for pt in pts {
            x += pt.x
            y += pt.y
        }
        let len = Double(pts.count)
        return Pt2D(x / len, y / len)
    }

    public static func approxDedupe(_ pts: [Pt2D], _ threshold: Distance) -> [Pt2D] {
        precondition(threshold != epsilonDist)
        var result: [Pt2D] = []
        for pt in pts where result.isEmpty || !result.last!.approxEq(pt, threshold) {
            result.append(pt)
        }
        return result
    }

    @inlinable public func toHashable() -> HashablePt2D { HashablePt2D(x: x, y: y) }

    public var description: String { "Pt2D(\(rustDisplay(x)), \(rustDisplay(y)))" }
}

extension Pt2D: Equatable {
    /// geom's `PartialEq`: within `epsilonDist`. Not transitive, as in geom.
    @inlinable
    public static func == (a: Pt2D, b: Pt2D) -> Bool { a.approxEq(b, epsilonDist) }
}

extension Array where Element == Pt2D {
    /// Rust's `Vec::dedup` with geom's approximate `PartialEq`: drops each
    /// point equal to the last one kept.
    @inlinable
    public mutating func dedup() {
        guard count > 1 else { return }
        var kept = 1
        for i in 1..<count where self[i] != self[kept - 1] {
            self[kept] = self[i]
            kept += 1
        }
        removeLast(count - kept)
    }
}

/// A point with exact equality and hashing, geom's `HashablePt2D`. Its order
/// is Rust's derived `Ord`: by x, then y.
public struct HashablePt2D: Hashable, Comparable, Sendable {
    public let x: Double
    public let y: Double

    @inlinable
    public init(x: Double, y: Double) {
        precondition(!x.isNaN && !y.isNaN)
        self.x = x
        self.y = y
    }

    public func toPt2D() -> Pt2D { Pt2D(x, y) }

    public static func < (a: HashablePt2D, b: HashablePt2D) -> Bool {
        a.x != b.x ? a.x < b.x : a.y < b.y
    }
}

/// A longitude and latitude. Ordered as Rust derives it: longitude, then latitude.
public struct LonLat: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let longitude: Double
    public let latitude: Double

    /// Note the order of arguments.
    public init(_ lon: Double, _ lat: Double) {
        precondition(!lon.isNaN && !lat.isNaN)
        longitude = lon
        latitude = lat
    }

    public var x: Double { longitude }
    public var y: Double { latitude }

    /// To world space. Can go out of bounds.
    public func toPt(_ b: GPSBounds) -> Pt2D {
        let max = b.getMaxWorldPt()
        let width = max.x
        let height = max.y
        let x = (self.x - b.minLon) / (b.maxLon - b.minLon) * width
        // Invert y, so the northernmost latitude is 0.
        let y = height - ((self.y - b.minLat) / (b.maxLat - b.minLat) * height)
        return Pt2D(x, y)
    }

    /// The Haversine distance.
    func gpsDist(_ other: LonLat) -> Distance {
        let earthRadiusM = 6_371_000.0
        let lon1 = toRadians(x)
        let lon2 = toRadians(other.x)
        let lat1 = toRadians(y)
        let lat2 = toRadians(other.y)
        let deltaLat = lat2 - lat1
        let deltaLon = lon2 - lon1
        let s1 = sin(deltaLat / 2.0)
        let s2 = sin(deltaLon / 2.0)
        let a = s1 * s1 + s2 * s2 * cos(lat1) * cos(lat2)
        let c = 2.0 * atan2(a.squareRoot(), (1.0 - a).squareRoot())
        return .meters(earthRadiusM * c)
    }

    public static func center(_ pts: [LonLat]) -> LonLat {
        precondition(!pts.isEmpty, "Can't find center of 0 points")
        var x = 0.0
        var y = 0.0
        for pt in pts {
            x += pt.x
            y += pt.y
        }
        let len = Double(pts.count)
        return LonLat(x / len, y / len)
    }

    public static func < (a: LonLat, b: LonLat) -> Bool {
        a.longitude != b.longitude ? a.longitude < b.longitude : a.latitude < b.latitude
    }

    public var description: String { "LonLat(\(rustDisplay(x)), \(rustDisplay(y)))" }
}
