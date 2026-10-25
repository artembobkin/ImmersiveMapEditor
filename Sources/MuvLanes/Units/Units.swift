/// muv-osm's physical units (`units/physical.rs`, the `dec_unit!` macro):
/// each a `simple_enum!` with its OSM names, its factor to the first unit,
/// and a conversion through that unit (`value * from / to`, in `Number`
/// arithmetic). `Duration` has units without a factor and only converts
/// partly. `WalkSpeed` is a speed or walking pace, with the special forms
/// of `maxspeed` (`walk`, `DE:zone:30`, `RU:urban`-like `AT:30`). Only the
/// units the lane reading reaches are here.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// An `f32` constant as Rust reads the literal: correctly rounded from its
/// decimal text (Swift goes through `Double` on arm64, rounding twice).
func f32(_ literal: String) -> Float { Float(literal)! }

/// A `dec_unit!` enum: its factors to the default unit (nil where there is none).
public protocol DecUnit: SimpleEnum, PartialUnit {
    static var factors: [Float?] { get }
}

extension DecUnit {
    public static var partialDefault: Self? { allCases[0] }
    public static func unitFromOsmStr(_ s: String) -> Self? { fromOsmStr(s) }
    public var toBase: Number? { Self.factors[rawValue].map { Number($0) } }

    public func partialConvert(to: Self, value: Number) -> Number? {
        guard let a = toBase, let b = to.toBase else { return nil }
        return value * a / b
    }
}

/// A `dec_unit!` whose every unit has a factor.
public protocol FullDecUnit: DecUnit, FullUnit {}

extension FullDecUnit {
    public func convert(to: Self, value: Number) -> Number { value * toBase! / to.toBase! }
}

public enum Distance: Int, FullDecUnit {
    case metre, kilometre, millimetre, mile, nauticalMile, feet, inch

    public static let rustNames = ["Metre", "Kilometre", "Millimetre", "Mile", "NauticalMile", "Feet", "Inch"]
    public static let osmNames = makeOsmNames([
        .metre: ["m", "metre", "metres", "meter", "meters"],
        .kilometre: ["km", "kilometre", "kilometres", "kilometer", "kilometers"],
        .millimetre: ["mm", "millimetre", "millimetres", "millimeter", "millimeters"],
        .mile: ["mi", "mile", "miles"],
        .nauticalMile: ["nmi", "international nautical mile"],
        .feet: ["ft", "'", "feet"],
        .inch: ["in", "\"", "inch", "inches"],
    ])
    public static let factors: [Float?] = [1.0, 1000.0, f32("0.001"), f32("1609.344"), 1852.0, f32("0.3048"), f32("0.0254")]
}

public enum Frequency: Int, FullDecUnit {
    case hertz, kilohertz, megahertz

    public static let rustNames = ["Hertz", "Kilohertz", "Megahertz"]
    public static let osmNames = makeOsmNames([.hertz: ["Hz"], .kilohertz: ["kHz"], .megahertz: ["MHz"]])
    public static let factors: [Float?] = [1.0, 1000.0, 1_000_000.0]
}

public enum Voltage: Int, FullDecUnit {
    case volts, kilovolts

    public static let rustNames = ["Volts", "Kilovolts"]
    public static let osmNames = makeOsmNames([.volts: ["V"], .kilovolts: ["kV"]])
    public static let factors: [Float?] = [1.0, 1000.0]
}

public enum Speed: Int, FullDecUnit {
    case kilometresPerHour, milesPerHour, knots, metresPerSecond

    public static let rustNames = ["KilometresPerHour", "MilesPerHour", "Knots", "MetresPerSecond"]
    public static let osmNames = makeOsmNames([
        .kilometresPerHour: ["km/h", "kph", "kmh", "kmph"],
        .milesPerHour: ["mph"],
        .knots: ["knots"],
        .metresPerSecond: ["m/s", "m/sec"],
    ])
    public static let factors: [Float?] = [1.0, f32("1.609344"), f32("1.852"), f32("3.6")]
}

public enum Weight: Int, FullDecUnit {
    case tonne, kilogram, shortTon, longTon, poundMass, longHundredweight

    public static let rustNames = ["Tonne", "Kilogram", "ShortTon", "LongTon", "PoundMass", "LongHundredweight"]
    public static let osmNames = makeOsmNames([
        .tonne: ["t"], .kilogram: ["kg"], .shortTon: ["st", "ST", "ton", "tons"], .longTon: ["lt"],
        .poundMass: ["lbs", "lb"], .longHundredweight: ["cwt"],
    ])
    public static let factors: [Float?] = [1.0, f32("0.001"), f32("0.9071847"), f32("1.016047"), f32("0.00045359237"),
                                     f32("0.0508")]
}

public enum Duration: Int, DecUnit {
    case second, minute, hour, night, day, week, month, year

    public static let rustNames = ["Second", "Minute", "Hour", "Night", "Day", "Week", "Month", "Year"]
    public static let osmNames = makeOsmNames([
        .second: ["s", "second", "seconds", "sec", "secs"],
        .minute: ["min", "minute", "minutes"],
        .hour: ["h", "hour", "hours", "hr", "hrs", "hs"],
        .night: ["nights", "night"],
        .day: ["d", "day", "days", "ds"],
        .week: ["w", "week", "weeks"],
        .month: ["M", "month", "months"],
        .year: ["y", "year", "years", "ys", "a"],
    ])
    public static let factors: [Float?] = [1.0, 60.0, 3600.0, nil, nil, nil, nil, nil]
}

/// `WalkSpeed`: a speed unit, or walking pace.
public enum WalkSpeed: PartialUnit, Hashable {
    case speed(Speed)
    case walk

    public static var partialDefault: WalkSpeed? { .speed(.kilometresPerHour) }

    public static func unitFromOsmStr(_ s: String) -> WalkSpeed? {
        s == "walk" ? .walk : Speed.fromOsmStr(s).map { .speed($0) }
    }

    public func muvJSON() -> MuvJSON {
        switch self {
        case .speed(let s): return .string(s.rustName)
        case .walk: return .string("Walk")
        }
    }

    public static func fromSpecialQuantityOsmStr(_ s: String) -> Quantity<WalkSpeed>? {
        if s == "walk" { return Quantity(Number(Float(1.0)), .walk) }
        if let (_, after) = s.rustSplitOnce("zone") {
            let speedStr = after.rustTrimStartMatches(UInt8(ascii: ":"))
            guard let speed = Number.fromOsmStr(speedStr) else { return nil }
            return Quantity(speed, .speed(.kilometresPerHour))
        }
        guard let (_, speedStr) = s.rustSplitOnce(":") else { return nil }
        if speedStr == "walk" { return Quantity(Number(Float(1.0)), .walk) }
        return Quantity.fromOsmStrWithUnitFnBase(speedStr) { partialDefault }
    }

    public func partialConvert(to: WalkSpeed, value: Number) -> Number? {
        switch (self, to) {
        case (.speed(let from), .speed(let to)): return from.partialConvert(to: to, value: value)
        case (.walk, .walk): return value
        default: return nil
        }
    }
}

extension Quantity where U == Speed {
    /// `From<Quantity<Speed>> for Quantity<WalkSpeed>`.
    var walkSpeed: Quantity<WalkSpeed> { Quantity<WalkSpeed>(value, .speed(unit)) }
}
