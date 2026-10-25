/// muv-osm's conditional restrictions (`conditional.rs`): a value with the
/// conditions under which it holds (`maxspeed:conditional=60 @ (22:00-05:00
/// AND weight>7.5)`), a list of them read from a key and its `:conditional`,
/// and the conditions themselves. Only reading and writing: osm2lanes
/// evaluates them only for a date, which the pipeline never gives.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// `Restriction<T>`: serde writes the conditions only when there are some.
public struct Restriction<T> {
    public var value: T
    public var conditions: [Condition]
}

extension Restriction: Equatable where T: Equatable {}

extension Restriction: MuvSerialize where T: MuvSerialize {
    public func muvJSON() -> MuvJSON {
        var map: [String: MuvJSON] = ["value": value.muvJSON()]
        if !conditions.isEmpty { map["conditions"] = conditions.muvJSON() }
        return .object(map)
    }
}

/// `Conditional<T>`: the restrictions in order, the unconditional value first if any.
public struct Conditional<T> {
    public var restrictions: [Restriction<T>]

    init(_ restrictions: [Restriction<T>]) { self.restrictions = restrictions }

    /// `From<T>`: the value with no condition.
    init(_ value: T) { restrictions = [Restriction(value: value, conditions: [])] }

    var count: Int { restrictions.count }
    var isEmpty: Bool { restrictions.isEmpty }
    var first: Restriction<T>? { restrictions.first }

    /// `Conditional::base`: the first value, if it has no condition.
    public var base: T? {
        guard let r = restrictions.first, r.conditions.isEmpty else { return nil }
        return r.value
    }

    /// `FromOsm for Conditional<F>` with `parse` as `F::from_osm_str`.
    static func fromOsm<Tl: Taglike>(_ tags: Tl, _ parse: (String) -> T?) -> Conditional<T>? {
        parseWith(tags, parse)
    }

    /// `Conditional::parse_with`: the tag's value, then each part of its
    /// `conditional` subtag split at the semicolons outside parentheses and
    /// quotes, at most 50 in all.
    static func parseWith<Tl: Taglike>(_ tags: Tl, _ f: (String) -> T?) -> Conditional<T>? {
        var restrictions: [Restriction<T>] = []
        if let v = tags.value, let d = f(v) { restrictions.append(Restriction(value: d, conditions: [])) }
        let conditional = tags.getValue("conditional") ?? ""
        var parensDepth: UInt32 = 0
        var inQuotes = false
        var parts: [String] = []
        var current: [UInt8] = []
        for b in conditional.utf8 {
            var split = false
            if b == UInt8(ascii: "\"") {
                inQuotes.toggle()
            } else if !inQuotes {
                switch b {
                case UInt8(ascii: "("): parensDepth = parensDepth == .max ? .max : parensDepth + 1
                case UInt8(ascii: ")"): parensDepth = parensDepth == 0 ? 0 : parensDepth - 1
                case UInt8(ascii: ";") where parensDepth == 0: split = true
                default: break
                }
            }
            if split {
                parts.append(String(decoding: current, as: UTF8.self))
                current = []
            } else {
                current.append(b)
            }
        }
        parts.append(String(decoding: current, as: UTF8.self))
        for part in parts {
            if restrictions.count >= 50 { break }
            if let r = Restriction<T>.parseOsm(part, f) { restrictions.append(r) }
        }
        return restrictions.isEmpty ? nil : Conditional(restrictions)
    }

    /// `Conditional::map`.
    func map<R>(_ f: (T) -> R) -> Conditional<R> {
        Conditional<R>(restrictions.map { Restriction(value: f($0.value), conditions: $0.conditions) })
    }

    /// `Conditional::merge`: every pair of restrictions, the conditions of both.
    func merge<O, R>(_ other: Conditional<O>, _ f: (T, O) -> R) -> Conditional<R> {
        var res: [Restriction<R>] = []
        for left in restrictions {
            for right in other.restrictions {
                res.append(Restriction(value: f(left.value, right.value), conditions: left.conditions + right.conditions))
            }
        }
        return Conditional<R>(res)
    }
}

extension Conditional: Equatable where T: Equatable {}

extension Conditional: MuvSerialize where T: MuvSerialize {
    public func muvJSON() -> MuvJSON { restrictions.muvJSON() }
}

extension Restriction {
    /// `Restriction::parse_osm`: `value @ conditions`, the conditions joined by ` AND `.
    static func parseOsm(_ part: String, _ f: (String) -> T?) -> Restriction<T>? {
        guard let (left, right) = part.rustSplitOnce("@") else { return nil }
        guard let value = f(removeParens(left)) else { return nil }
        var conditions: [Condition] = []
        for c in removeParens(right).rustSplit(" AND ") {
            guard let condition = Condition.fromOsmStr(c) else { return nil }
            conditions.append(condition)
        }
        return Restriction(value: value, conditions: conditions)
    }
}

/// `remove_parens`: trimmed, then as many enclosing parentheses removed as
/// both ends have, counting those that close inside.
func removeParens(_ input: String) -> String {
    let s = input.rustTrim()
    let scalars = Array(s.unicodeScalars)
    // Byte offsets of the scalars.
    var offsets: [Int] = []
    var o = 0
    for c in scalars {
        offsets.append(o)
        o += String(c).utf8.count
    }
    var endCount = 0
    var endI = 0
    for k in scalars.indices.reversed() {
        if scalars[k] == ")" {
            endCount += 1
        } else {
            endI = offsets[k]
            break
        }
    }
    var quotes = false
    var startCount: UInt32 = 0
    var k = 0
    while k < scalars.count {
        let c = scalars[k]
        k += 1
        if c == "(" {
            startCount = startCount == .max ? .max : startCount + 1
        } else if c == ")" {
            startCount = startCount == 0 ? 0 : startCount - 1
        } else if c == "\"" {
            quotes = true
            break
        } else {
            break
        }
    }
    var midCount = 0
    while k < scalars.count {
        let i = offsets[k], c = scalars[k]
        k += 1
        if i >= endI { break }
        if c == "\"" {
            quotes.toggle()
        } else if !quotes {
            if c == "(" {
                midCount += 1
            } else if c == ")" {
                if midCount > 0 { midCount -= 1 } else { startCount = startCount == 0 ? 0 : startCount - 1 }
            }
        }
    }
    let i = min(endCount, Int(startCount))
    let bytes = Array(s.utf8)
    return String(decoding: bytes[i..<(bytes.count - i)], as: UTF8.self)
}

extension Restriction: Sendable where T: Sendable {}
extension Conditional: Sendable where T: Sendable {}
