/// geom's `Speed`: metres per second, trimmed like `Distance`.

public struct Speed: Hashable, Comparable, Sendable {
    public let value: Double

    public static let zero = Speed(constMetersPerSecond: 0.0)

    public init(constMetersPerSecond value: Double) { self.value = value }

    public static func metersPerSecond(_ value: Double) -> Speed {
        precondition(value.isFinite, "Bad Speed \(value)")
        return Speed(constMetersPerSecond: trimF64(value))
    }

    public static func milesPerHour(_ value: Double) -> Speed { .metersPerSecond(0.44704 * value) }
    public static func kmPerHour(_ value: Double) -> Speed { .metersPerSecond(0.277778 * value) }

    public var innerMetersPerSecond: Double { value }

    public static func < (a: Speed, b: Speed) -> Bool { a.value < b.value }

    /// Rust's derived `Debug`: `Speed(8.3333)`.
    public var rustDebug: String { "Speed(\(rustDebugF64(value)))" }
}
