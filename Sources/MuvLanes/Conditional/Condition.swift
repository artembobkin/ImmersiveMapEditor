/// muv-osm's `Condition`, `Compare` and `Operator` (`conditional.rs`): the
/// conditions of a restriction (`wet`, `weight>7.5`, an opening-hours
/// range, an access level) as read from OSM and written by serde (unit
/// variants as their name, the others as a one-key map).
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

public enum Operator: Int, SimpleEnum, Sendable {
    case less, lessEqual, equal, greater, greaterEqual

    public static let rustNames = ["Less", "LessEqual", "Equal", "Greater", "GreaterEqual"]
    public static let osmNames = makeOsmNames([.less: ["<"], .lessEqual: ["<="], .equal: ["="], .greater: [">"],
                                        .greaterEqual: [">="]])

    /// `Operator::parse`: the text before the first comparison sign, the
    /// operator, and the text after it.
    static func parse(_ s: String) -> (String, Operator, String)? {
        let b = Array(s.utf8)
        var i = 0
        func str(_ r: Range<Int>) -> String { String(decoding: b[r], as: UTF8.self) }
        while i < b.count {
            switch b[i] {
            case UInt8(ascii: "<"):
                if i + 1 < b.count, b[i + 1] == UInt8(ascii: "=") { return (str(0..<i), .lessEqual, str((i + 2)..<b.count)) }
                return (str(0..<i), .less, str((i + 1)..<b.count))
            case UInt8(ascii: "="):
                return (str(0..<i), .equal, str((i + 1)..<b.count))
            case UInt8(ascii: ">"):
                if i + 1 < b.count, b[i + 1] == UInt8(ascii: "=") { return (str(0..<i), .greaterEqual, str((i + 2)..<b.count)) }
                return (str(0..<i), .greater, str((i + 1)..<b.count))
            default:
                i += 1
            }
        }
        return nil
    }
}

/// `Compare`: what a comparison condition measures.
public enum Compare: Equatable, Sendable, MuvSerialize {
    case weight(Quantity<Weight>)
    case weightrating(Quantity<Weight>)
    case weightcapacity(Quantity<Weight>)
    case emptyweight(Quantity<Weight>)
    case axleload(Quantity<Weight>)
    case length(Quantity<Distance>)
    case width(Quantity<Distance>)
    case height(Quantity<Distance>)
    case wheels(UInt32)
    case draught(Quantity<Distance>)
    case occupants(UInt32)
    case stay(Quantity<Duration>)
    case seats(UInt32)
    case axles(UInt32)
    case trailers(UInt32)
    case trailerWeight(Quantity<Weight>)

    /// `Compare::parse`.
    static func parse(_ unit: String, _ value: String) -> Compare? {
        let weight = { Quantity<Weight>.fromOsmStr(value) }
        let distance = { Quantity<Distance>.fromOsmStr(value) }
        let count = { rustParseU32(value) }
        switch unit {
        case "weight": return weight().map { .weight($0) }
        case "weightrating": return weight().map { .weightrating($0) }
        case "weightcapacity": return weight().map { .weightcapacity($0) }
        case "emptyweight": return weight().map { .emptyweight($0) }
        case "axleload": return weight().map { .axleload($0) }
        case "length": return distance().map { .length($0) }
        case "width": return distance().map { .width($0) }
        case "height": return distance().map { .height($0) }
        case "wheels": return count().map { .wheels($0) }
        case "draught": return distance().map { .draught($0) }
        case "occupants": return count().map { .occupants($0) }
        case "stay": return Quantity<Duration>.fromOsmStr(value).map { .stay($0) }
        case "seats": return count().map { .seats($0) }
        case "axles": return count().map { .axles($0) }
        case "trailers": return count().map { .trailers($0) }
        case "trailerweight": return weight().map { .trailerWeight($0) }
        default: return nil
        }
    }

    public func muvJSON() -> MuvJSON {
        let (name, value): (String, MuvJSON)
        switch self {
        case .weight(let q): (name, value) = ("Weight", q.muvJSON())
        case .weightrating(let q): (name, value) = ("Weightrating", q.muvJSON())
        case .weightcapacity(let q): (name, value) = ("Weightcapacity", q.muvJSON())
        case .emptyweight(let q): (name, value) = ("Emptyweight", q.muvJSON())
        case .axleload(let q): (name, value) = ("Axleload", q.muvJSON())
        case .length(let q): (name, value) = ("Length", q.muvJSON())
        case .width(let q): (name, value) = ("Width", q.muvJSON())
        case .height(let q): (name, value) = ("Height", q.muvJSON())
        case .wheels(let n): (name, value) = ("Wheels", n.muvJSON())
        case .draught(let q): (name, value) = ("Draught", q.muvJSON())
        case .occupants(let n): (name, value) = ("Occupants", n.muvJSON())
        case .stay(let q): (name, value) = ("Stay", q.muvJSON())
        case .seats(let n): (name, value) = ("Seats", n.muvJSON())
        case .axles(let n): (name, value) = ("Axles", n.muvJSON())
        case .trailers(let n): (name, value) = ("Trailers", n.muvJSON())
        case .trailerWeight(let q): (name, value) = ("TrailerWeight", q.muvJSON())
        }
        return .object([name: value])
    }
}

/// `Condition`.
public enum Condition: Equatable, Sendable, MuvSerialize {
    case dateTimeRange(DateTimeRange)
    case winter, summer, wet, snow
    case compare(Operator, Compare)
    case accessLevel(AccessLevel)
    case trailer, caravan, articulated

    /// `FromOsmStr for Condition`.
    static func fromOsmStr(_ input: String) -> Condition? {
        let s = removeParens(input)
        switch s {
        case "winter": return .winter
        case "summer": return .summer
        case "wet": return .wet
        case "snow": return .snow
        case "trailer": return .trailer
        case "caravan": return .caravan
        case "articulated": return .articulated
        default:
            if let level = AccessLevel.fromOsmStr(s) { return .accessLevel(level) }
            if let range = DateTimeRange.fromOsmStr(s) { return .dateTimeRange(range) }
            guard let (left, op, right) = Operator.parse(s),
                  let compare = Compare.parse(left.rustTrimEnd(), right.rustTrimStart()) else { return nil }
            return .compare(op, compare)
        }
    }

    public func muvJSON() -> MuvJSON {
        switch self {
        case .dateTimeRange(let r): return .object(["DateTimeRange": .string(r.text)])
        case .winter: return .string("Winter")
        case .summer: return .string("Summer")
        case .wet: return .string("Wet")
        case .snow: return .string("Snow")
        case .compare(let op, let c): return .object(["Compare": .array([op.muvJSON(), c.muvJSON()])])
        case .accessLevel(let a): return .object(["AccessLevel": a.muvJSON()])
        case .trailer: return .string("Trailer")
        case .caravan: return .string("Caravan")
        case .articulated: return .string("Articulated")
        }
    }
}

/// `DateTimeRange`: an opening-hours expression, kept as its text (which
/// serde writes and equality compares), accepted only if the
/// opening-hours crate parses it.
public struct DateTimeRange: Equatable, Sendable {
    public let text: String

    static func fromOsmStr(_ s: String) -> DateTimeRange? {
        OpeningHoursSyntax.parses(s) ? DateTimeRange(text: s) : nil
    }
}
