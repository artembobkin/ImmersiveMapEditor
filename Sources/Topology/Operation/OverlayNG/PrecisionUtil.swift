import Foundation

/// Precision scales for robust overlay: the safe scale keeps the inputs'
/// largest ordinate within the digits a double holds exactly: JTS's
/// `PrecisionUtil` (the parts OverlayNG uses).
public enum PrecisionUtil {
    public static let maxRobustDPDigits: Int32 = 14

    public static func safeScale(_ value: Double) -> Double { precisionScale(value, maxRobustDPDigits) }

    public static func safeScale(_ geom: Geometry) -> Double { safeScale(maxBoundMagnitude(geom.getEnvelopeInternal())) }

    public static func safeScale(_ a: Geometry, _ b: Geometry?) -> Double {
        var maxBnd = maxBoundMagnitude(a.getEnvelopeInternal())
        if let b { maxBnd = cxxMax(maxBnd, maxBoundMagnitude(b.getEnvelopeInternal())) }
        return safeScale(maxBnd)
    }

    /// The largest ordinate magnitude of an envelope. GEOS 3.13's null
    /// envelope (of an empty geometry) has NaN ordinates, JTS's 0 and -1:
    /// GEOS's NaN loses every `std::max` it is the second of, so an empty
    /// second input leaves the scale to the first, as here.
    private static func maxBoundMagnitude(_ env: Envelope) -> Double {
        if env.isNull { return .nan }
        return cxxMax(cxxMax(abs(env.maxX), abs(env.maxY)), cxxMax(abs(env.minX), abs(env.minY)))
    }

    /// The power of ten that leaves `precisionDigits` digits for a value of
    /// this magnitude. The magnitude is a 32-bit integer cast as on the
    /// JVM and on arm64 (saturating, NaN to 0), the difference wrapping.
    private static func precisionScale(_ value: Double, _ precisionDigits: Int32) -> Double {
        let magnitude = int32Cast(log(value) / log(10) + 1.0)
        let precDigits = precisionDigits &- magnitude
        return pow(10.0, Double(precDigits))
    }
}

/// `std::max` of doubles: the first unless it is less than the second.
@inline(__always) func cxxMax(_ a: Double, _ b: Double) -> Double { a < b ? b : a }

/// `std::min` of doubles: the first unless the second is less.
@inline(__always) func cxxMin(_ a: Double, _ b: Double) -> Double { b < a ? b : a }

/// A double cast to a 32-bit integer as Java's `(int)` and arm64's
/// conversion do it: toward zero, saturating, NaN to 0.
@inline(__always) func int32Cast(_ v: Double) -> Int32 {
    if v.isNaN { return 0 }
    if v >= 2147483647.0 { return Int32.max }
    if v <= -2147483648.0 { return Int32.min }
    return Int32(v)
}
