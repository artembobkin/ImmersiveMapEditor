/// geom's `Distance`: metres, trimmed to four decimals on every
/// construction, as geom's `trim_f64` does, so arithmetic on distances
/// rounds the same way the Rust does.

/// The revision of geom this target follows.
public enum StreetGeomPort {
    public static let source = "geom 9bb49fc"
}

/// geom's `trim_f64`: rounds to four decimals (half away from zero, as
/// Rust's `f64::round`).
@inlinable
public func trimF64(_ x: Double) -> Double {
    (x * 10_000.0).rounded() / 10_000.0
}

/// A distance in metres. Can be negative. Finite and trimmed by construction.
public struct Distance: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The raw value in metres (Rust's `.0`).
    public let value: Double

    public static let zero = Distance(constMeters: 0.0)

    /// geom's `Distance::meters`: panics on a non-finite value, trims.
    @inlinable
    public static func meters(_ value: Double) -> Distance {
        precondition(value.isFinite, "Bad Distance \(value)")
        return Distance(constMeters: trimF64(value))
    }

    /// geom's `const_meters`: the value as it is, untrimmed.
    @inlinable
    public init(constMeters value: Double) { self.value = value }

    public static func inches(_ value: Double) -> Distance { .meters(0.0254 * value) }
    public static func miles(_ value: Double) -> Distance { .meters(1609.34 * value) }
    public static func centimeters(_ value: Int) -> Distance { .meters(Double(value) / 100.0) }
    public static func feet(_ value: Double) -> Distance { .meters(value * 0.3048) }

    @inlinable
    public func abs() -> Distance { value > 0.0 ? self : Distance(constMeters: -value) }

    public func sqrt() -> Distance { .meters(value.squareRoot()) }

    @inlinable
    public var innerMeters: Double { value }

    public func toFeet() -> Double { value * 3.28084 }

    /// self / other, or 0 when other is zero.
    public func safePercent(_ other: Distance) -> Double {
        if other == .zero { return 0.0 }
        return self / other
    }

    /// Rust's `Display`: the value then "m".
    public var description: String { "\(rustDisplay(value))m" }

    public static func < (a: Distance, b: Distance) -> Bool { a.value < b.value }

    @inlinable public static func + (a: Distance, b: Distance) -> Distance { .meters(a.value + b.value) }
    @inlinable public static func - (a: Distance, b: Distance) -> Distance { .meters(a.value - b.value) }
    @inlinable public static prefix func - (a: Distance) -> Distance { .meters(-a.value) }
    @inlinable public static func += (a: inout Distance, b: Distance) { a = a + b }
    @inlinable public static func -= (a: inout Distance, b: Distance) { a = a - b }
    @inlinable public static func * (a: Distance, s: Double) -> Distance { .meters(a.value * s) }
    @inlinable public static func * (s: Double, a: Distance) -> Distance { .meters(s * a.value) }
    @inlinable public static func *= (a: inout Distance, s: Double) { a = a * s }

    @inlinable
    public static func / (a: Distance, b: Distance) -> Double {
        precondition(b != .zero, "Can't divide \(a) / \(b)")
        return a.value / b.value
    }

    @inlinable
    public static func / (a: Distance, s: Double) -> Distance {
        precondition(s != 0.0, "Can't divide \(a) / \(s)")
        return .meters(a.value / s)
    }
}

extension Sequence where Element == Distance {
    /// Rust's `Sum` for `Distance`: adds one at a time from zero, trimming each time.
    public func sum() -> Distance {
        var total = Distance.zero
        for x in self { total += x }
        return total
    }
}

/// About 0.4 inches.
public let epsilonDist = Distance(constMeters: 0.01)
