/// muv-osm's legal default speeds (`lanes/highway/speed_default.rs`):
/// `default(country, class)` and the per-class lookups, over the generated
/// table of `SpeedDefaultTable.swift`, decoded once. Each value is a pair:
/// the minimum and the maximum speeds per mode.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `DefaultSpeed`.
typealias DefaultSpeed = TModes<Conditional<Quantity<WalkSpeed>>>

enum SpeedDefault {
    /// `default(country, class)`, the class one of `urban`, `rural`,
    /// `motorway` and the like, the country a region code (`RU`, `US-TX`).
    static func lookup(_ country: String, _ cls: String) -> (DefaultSpeed, DefaultSpeed)? {
        guard let table = classes[cls].flatMap({ byClass[$0] }), let function = table[country] else { return nil }
        return decoded[function]
    }

    /// The table's lines by kind.
    private struct Lines {
        var dateRanges: [String] = []
        var encoded: [(String, String)] = []
        var byClass: [String: [String: String]] = [:]
        var classes: [String: String] = [:]
    }

    private static let lines: Lines = {
        var l = Lines()
        for line in table.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch f[0] {
            case "R": l.dateRanges.append(f[1])
            case "F": l.encoded.append((f[1], f[2]))
            case "D": l.byClass[f[1], default: [:]][f[2]] = f[3]
            case "C": l.classes[f[1]] = f[2]
            default: fatalError("speed table line \(line)")
            }
        }
        return l
    }()

    private static var dateRanges: [String] { lines.dateRanges }
    private static var byClass: [String: [String: String]] { lines.byClass }
    private static var classes: [String: String] { lines.classes }

    private static let decoded: [String: (DefaultSpeed, DefaultSpeed)] = {
        var res: [String: (DefaultSpeed, DefaultSpeed)] = [:]
        for (name, text) in lines.encoded {
            let maps = text.rustSplit("|")
            res[name] = (decodeModes(maps[0]), decodeModes(maps[1]))
        }
        return res
    }()

    private static func decodeModes(_ s: String) -> DefaultSpeed {
        var modes = DefaultSpeed()
        if s.isEmpty { return modes }
        for entry in s.rustSplit(",") {
            let (name, restrictions) = entry.rustSplitOnce("=")!
            let mode = TMode.allCases[TMode.rustNames.firstIndex(of: name)!]
            modes.set(mode, Conditional(restrictions.rustSplit(";").map(decodeRestriction)))
        }
        return modes
    }

    private static func decodeRestriction(_ s: String) -> Restriction<Quantity<WalkSpeed>> {
        let parts = s.rustSplit("@")
        let (number, unit) = splitUnit(parts[0])
        let speed: WalkSpeed
        switch unit {
        case "k": speed = .speed(.kilometresPerHour)
        case "m": speed = .speed(.milesPerHour)
        case "w": speed = .walk
        default: fatalError("unit \(unit)")
        }
        let conditions = parts.count > 1 ? parts[1].rustSplit("&").map(decodeCondition) : []
        return Restriction(value: Quantity(number, speed), conditions: conditions)
    }

    /// A number and its unit letters.
    private static func splitUnit(_ s: String) -> (Number, String) {
        if s.hasPrefix("inf") { return (Number(Float.infinity), String(s.dropFirst(3))) }
        let digits = s.prefix { $0.isNumber || $0 == "." }
        return (Number(f32(String(digits))), String(s.dropFirst(digits.count)))
    }

    private static func decodeCondition(_ s: String) -> Condition {
        switch s {
        case "T": return .trailer
        case "C": return .caravan
        case "A": return .articulated
        case "W": return .wet
        default: break
        }
        if let index = s.rustStripPrefix("D") {
            return .dateTimeRange(DateTimeRange.fromOsmStr(dateRanges[Int(index)!])!)
        }
        let op: Operator
        switch s.first! {
        case ">": op = .greater
        case "g": op = .greaterEqual
        case "<": op = .less
        case "l": op = .lessEqual
        case "=": op = .equal
        default: fatalError("operator \(s)")
        }
        let (kind, value) = String(s.dropFirst()).rustSplitOnce(":")!
        func weight() -> Quantity<Weight> {
            let (n, u) = splitUnit(value)
            switch u {
            case "t": return Quantity(n, .tonne)
            case "p": return Quantity(n, .poundMass)
            case "s": return Quantity(n, .shortTon)
            default: fatalError("weight \(u)")
            }
        }
        func distance() -> Quantity<Distance> {
            let (n, u) = splitUnit(value)
            switch u {
            case "M": return Quantity(n, .metre)
            case "f": return Quantity(n, .feet)
            default: fatalError("distance \(u)")
            }
        }
        let compare: Compare
        switch kind {
        case "Weight": compare = .weight(weight())
        case "Weightrating": compare = .weightrating(weight())
        case "Weightcapacity": compare = .weightcapacity(weight())
        case "Emptyweight": compare = .emptyweight(weight())
        case "Axleload": compare = .axleload(weight())
        case "TrailerWeight": compare = .trailerWeight(weight())
        case "Length": compare = .length(distance())
        case "Width": compare = .width(distance())
        case "Height": compare = .height(distance())
        case "Draught": compare = .draught(distance())
        case "Wheels": compare = .wheels(UInt32(value)!)
        case "Occupants": compare = .occupants(UInt32(value)!)
        case "Seats": compare = .seats(UInt32(value)!)
        case "Axles": compare = .axles(UInt32(value)!)
        case "Trailers": compare = .trailers(UInt32(value)!)
        default: fatalError("compare \(kind)")
        }
        return .compare(op, compare)
    }
}
