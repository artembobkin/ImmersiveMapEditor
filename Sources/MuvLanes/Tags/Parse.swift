/// muv-osm's parsing of OSM values (`parse.rs`, the `FromOsmStr` and
/// `ToOsmStr` derives, `simple_enum!`): a C-like enum reads its OSM names
/// ASCII-case-insensitively (the snake case of each variant, or the names
/// its `osm_str` attribute lists, none for `osm_str()`), and serde writes
/// it by its Rust variant name. Also the plain value parsers and the
/// semicolon-separated values.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// The OSM names of an enum's variants, read as the derived
/// `FromOsmStr` reads them: the whole string, ignoring ASCII case.
public struct OsmNames<E: Hashable & Sendable>: Sendable {
    private let lookup: [String: E]

    /// `variants` in declaration order with their Rust names, `aliases`
    /// replacing the snake-case name of a variant (empty: no name at all).
    init(_ variants: [(E, String)], aliases: [E: [String]] = [:]) {
        var lookup: [String: E] = [:]
        for (e, rustName) in variants {
            for name in aliases[e] ?? [pascalToSnake(rustName)] {
                lookup[asciiLowercased(name)] = e
            }
        }
        self.lookup = lookup
    }

    func parse(_ s: String) -> E? { lookup[asciiLowercased(s)] }
}

/// The derive's `pascal_to_snake`: an underscore before every capital but the first.
func pascalToSnake(_ s: String) -> String {
    var res = ""
    for c in s.unicodeScalars {
        if c.properties.isUppercase {
            if !res.isEmpty { res.append("_") }
            res.append(contentsOf: c.properties.lowercaseMapping)
        } else {
            res.unicodeScalars.append(c)
        }
    }
    return res
}

/// ASCII letters lowered, every other byte kept, as `IgnoreAsciiCase` compares.
func asciiLowercased(_ s: String) -> String {
    var bytes = Array(s.utf8)
    var changed = false
    for i in bytes.indices where bytes[i] >= 0x41 && bytes[i] <= 0x5A {
        bytes[i] += 0x20
        changed = true
    }
    return changed ? String(decoding: bytes, as: UTF8.self) : s
}

/// A `simple_enum!`: Copy, ordered by declaration, its OSM names, and serde
/// writing the variant's Rust name.
public protocol SimpleEnum: RawRepresentable, CaseIterable, Hashable, Sendable, MuvSerialize where AllCases == [Self], RawValue == Int {
    /// The Rust variant names, in declaration order.
    static var rustNames: [String] { get }
    static var osmNames: OsmNames<Self> { get }
}

extension SimpleEnum {
    public var ordinal: Int { rawValue }
    public var rustName: String { Self.rustNames[ordinal] }
    public static func fromOsmStr(_ s: String) -> Self? { osmNames.parse(s) }
    public func muvJSON() -> MuvJSON { .string(rustName) }

    /// The `OsmNames` of an enum whose cases are listed in `rustNames` order.
    static func makeOsmNames(_ aliases: [Self: [String]] = [:]) -> OsmNames<Self> {
        OsmNames(Array(zip(allCases, rustNames)), aliases: aliases)
    }
}

/// `FromOsmStr for bool`: exactly `yes` or `no`.
func boolFromOsmStr(_ s: String) -> Bool? {
    switch s {
    case "yes": return true
    case "no": return false
    default: return nil
    }
}

/// `SeperatedValues`: the values between semicolons, `;;` a literal semicolon.
func seperatedValues(_ str: String) -> [String] {
    var result: [String] = []
    var rest: String? = str
    while let s = rest {
        guard let (valuePart, after) = s.rustSplitOnce(";") else {
            rest = nil
            result.append(s)
            break
        }
        guard var nextPart = after.rustStripPrefix(";") else {
            rest = after
            result.append(valuePart)
            continue
        }
        var value = valuePart
        while true {
            value += ";"
            guard let (part, after2) = nextPart.rustSplitOnce(";") else {
                rest = nil
                value += nextPart
                result.append(value)
                break
            }
            value += part
            guard let newPart = after2.rustStripPrefix(";") else {
                rest = after2
                result.append(value)
                break
            }
            nextPart = newPart
        }
    }
    return result
}
