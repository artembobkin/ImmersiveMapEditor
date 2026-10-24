/// geom's `Angle`: radians, rounded to seven decimals on construction.

import Foundation

/// Rust's `f64::to_radians`: `self * (PI / 180)`.
@inlinable public func toRadians(_ degrees: Double) -> Double { degrees * (Double.pi / 180.0) }
/// Rust's `f64::to_degrees`: `self * (180 / PI)`.
@inlinable public func toDegrees(_ radians: Double) -> Double { radians * (180.0 / Double.pi) }

/// Rust's `%` on f64 (C's `fmod`).
@inlinable public func rustRem(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }

/// Rust's `f64::rem_euclid`.
@inlinable public func remEuclid(_ a: Double, _ b: Double) -> Double {
    let r = rustRem(a, b)
    return r < 0.0 ? r + Swift.abs(b) : r
}

public struct Angle: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Radians (Rust's `.0`).
    public let value: Double

    public static let zero = Angle(raw: 0.0)

    @usableFromInline init(raw: Double) { value = raw }

    /// Retains more precision than distances: seven decimals.
    @inlinable
    public static func newRads(_ rads: Double) -> Angle {
        Angle(raw: (rads * 10_000_000.0).rounded() / 10_000_000.0)
    }

    @inlinable public static func degrees(_ degs: Double) -> Angle { newRads(toRadians(degs)) }

    public func opposite() -> Angle { .newRads(value + Double.pi) }

    func invertY() -> Angle { .newRads(2.0 * Double.pi - value) }

    @inlinable public func rotateDegs(_ degrees: Double) -> Angle { .newRads(value + toRadians(degrees)) }

    /// [0, 2pi)
    @inlinable
    public func normalizedRadians() -> Double {
        value < 0.0 ? value + (2.0 * Double.pi) : value
    }

    /// [0, 360)
    public func normalizedDegrees() -> Double { toDegrees(normalizedRadians()) }

    /// [-180, 180]
    public func simpleShortestRotationTowards(_ other: Angle) -> Double {
        rustRem(normalizedDegrees() - other.normalizedDegrees() + 540.0, 360.0) - 180.0
    }

    public func shortestRotationTowards(_ other: Angle) -> Angle {
        .degrees(simpleShortestRotationTowards(other))
    }

    public func approxEq(_ other: Angle, _ withinDegrees: Double) -> Bool {
        Swift.abs(simpleShortestRotationTowards(other)) < withinDegrees
    }

    public func approxParallel(_ other: Angle, _ withinDegrees: Double) -> Bool {
        approxEq(other, withinDegrees) || opposite().approxEq(other, withinDegrees)
    }

    public func reorient() -> Angle {
        let theta = remEuclid(normalizedDegrees(), 360.0)
        var result = self
        if theta > 90.0 { result = result.opposite() }
        if theta > 270.0 { result = result.opposite() }
        return result
    }

    public static func average(_ input: [Angle]) -> Angle {
        let num = Double(input.count)
        var cosSum = 0.0
        var sinSum = 0.0
        for x in input {
            cosSum += cos(x.value)
            sinSum += sin(x.value)
        }
        return .newRads(atan2(sinSum / num, cosSum / num))
    }

    public static func < (a: Angle, b: Angle) -> Bool { a.value < b.value }
    public static func + (a: Angle, b: Angle) -> Angle { .newRads(a.value + b.value) }
    public static prefix func - (a: Angle) -> Angle { .newRads(-a.value) }

    public var description: String { "Angle(\(rustDisplay(normalizedDegrees())) degrees)" }
}
