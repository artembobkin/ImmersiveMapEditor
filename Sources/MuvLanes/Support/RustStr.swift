/// The parts of Rust's `str` and number parsing that Muv's lane reading
/// leans on, with Rust's semantics: `split` keeps empty pieces and works on
/// code points (never on grapheme clusters, as Swift's `Character` would),
/// `trim` removes Unicode `White_Space`, integers accept a leading `+`, and
/// `f32` parsing rounds correctly. Every pattern Muv splits on is ASCII, so
/// matching works on the UTF-8 bytes.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

extension String {
    /// `str::split(&str)` (a `char` pattern is its one-byte string): every
    /// piece, empty ones too (`"".split(';')` is `[""]`), non-overlapping
    /// matches from the left.
    func rustSplit(_ pattern: String) -> [String] {
        let s = Array(utf8), p = Array(pattern.utf8)
        var pieces: [String] = []
        var start = 0, i = 0
        while i + p.count <= s.count {
            if s[i..<(i + p.count)].elementsEqual(p) {
                pieces.append(String(decoding: s[start..<i], as: UTF8.self))
                i += p.count
                start = i
            } else {
                i += 1
            }
        }
        pieces.append(String(decoding: s[start...], as: UTF8.self))
        return pieces
    }

    /// `str::rsplit(char)`: the pieces of `rustSplit`, last first.
    func rustRSplit(_ pattern: String) -> [String] { rustSplit(pattern).reversed() }

    /// `str::split_once(&str)`.
    func rustSplitOnce(_ pattern: String) -> (String, String)? {
        let s = Array(utf8), p = Array(pattern.utf8)
        var i = 0
        while i + p.count <= s.count {
            if s[i..<(i + p.count)].elementsEqual(p) {
                return (String(decoding: s[..<i], as: UTF8.self), String(decoding: s[(i + p.count)...], as: UTF8.self))
            }
            i += 1
        }
        return nil
    }

    /// `str::strip_prefix(&str)`.
    func rustStripPrefix(_ prefix: String) -> String? {
        utf8.starts(with: prefix.utf8) ? String(decoding: utf8.dropFirst(prefix.utf8.count), as: UTF8.self) : nil
    }

    /// `str::trim`: Unicode `White_Space` removed at both ends.
    func rustTrim() -> String { rustTrimStart().rustTrimEnd() }

    /// `str::trim_start`.
    func rustTrimStart() -> String {
        let scalars = unicodeScalars
        guard let i = scalars.firstIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(scalars[i...])
    }

    /// `str::trim_end`.
    func rustTrimEnd() -> String {
        let scalars = unicodeScalars
        guard let i = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(scalars[...i])
    }

    /// `str::trim_start_matches(char)` for an ASCII character.
    func rustTrimStartMatches(_ c: UInt8) -> String {
        String(decoding: utf8.drop { $0 == c }, as: UTF8.self)
    }
}

/// Rust's `FromStr` for an unsigned integer no larger than `max`: an
/// optional `+`, then ASCII digits only, at least one, no overflow.
func rustParseUnsigned(_ s: String, max: UInt64) -> UInt64? {
    var bytes = Substring(s).utf8[...]
    if bytes.first == UInt8(ascii: "+") {
        bytes = bytes.dropFirst()
    }
    if bytes.isEmpty { return nil }
    var value: UInt64 = 0
    for b in bytes {
        guard b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") else { return nil }
        let (m, o1) = value.multipliedReportingOverflow(by: 10)
        let (a, o2) = m.addingReportingOverflow(UInt64(b - UInt8(ascii: "0")))
        if o1 || o2 || a > max { return nil }
        value = a
    }
    return value
}

/// `str::parse::<u8>()`.
func rustParseU8(_ s: String) -> UInt8? { rustParseUnsigned(s, max: UInt64(UInt8.max)).map { UInt8($0) } }

/// `str::parse::<u32>()`.
func rustParseU32(_ s: String) -> UInt32? { rustParseUnsigned(s, max: UInt64(UInt32.max)).map { UInt32($0) } }

/// `str::parse::<usize>()` on a 64-bit target.
func rustParseUsize(_ s: String) -> Int? {
    rustParseUnsigned(s, max: UInt64(UInt.max)).map { Int(clamping: $0) }
}

/// `str::parse::<f32>()` for the strings Muv hands it (an optional `-`,
/// digits and at most one `.`): correctly rounded, infinite past `f32::MAX`.
func rustParseF32(_ s: String) -> Float? {
    guard s.utf8.contains(where: { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return nil }
    return Float(s)
}
