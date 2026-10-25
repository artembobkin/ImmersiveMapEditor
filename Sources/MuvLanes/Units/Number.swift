/// muv-osm's `Number` (`units/number.rs`): an `f32` with its significant
/// figures as written in OSM (`u8::MAX` for exact), the figures carried
/// through arithmetic (the fewer of the two), and written by serde as the
/// string `Display` gives (rounded to the significant figures, with Rust's
/// exact float formatting).
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public struct Number: Sendable, MuvSerialize, Equatable {
    public private(set) var number: Float
    public var significantFigures: UInt8

    /// `Number::new`: exact, no NaN.
    init(_ num: Float) {
        precondition(!num.isNaN, "float expected not to be NaN")
        number = num
        significantFigures = .max
    }

    init(number: Float, significantFigures: UInt8) {
        self.number = number
        self.significantFigures = significantFigures
    }

    /// `From<u16> for Number`.
    init(_ value: UInt16) { self.init(Float(value)) }

    /// `Number::parse_start`: the number at the start of `s`, counting its
    /// significant figures, and the rest of `s`.
    static func parseStart(_ s: String) -> (Number, String)? {
        var decimal = false, digit = false
        var sig: UInt8 = 0, zeros: UInt8 = 0
        let bytes = Array(s.utf8)
        var i = 0
        loop: for b in bytes {
            switch b {
            case UInt8(ascii: "-") where i == 0:
                break
            case UInt8(ascii: "0") where !digit:
                break
            case UInt8(ascii: "0"):
                if decimal { sig = sig.saturatingAdd(1) } else { zeros = zeros.saturatingAdd(1) }
            case UInt8(ascii: "1")...UInt8(ascii: "9"):
                sig = sig.saturatingAdd(zeros.saturatingAdd(1))
                zeros = 0
                digit = true
            case UInt8(ascii: ".") where !decimal:
                decimal = true
            default:
                break loop
            }
            i += 1
        }
        guard let number = rustParseF32(String(decoding: bytes[..<i], as: UTF8.self)) else { return nil }
        return (Number(number: number, significantFigures: sig), String(decoding: bytes[i...], as: UTF8.self))
    }

    /// `FromOsmStr for Number`: the whole string a number.
    static func fromOsmStr(_ s: String) -> Number? {
        guard let (n, rest) = parseStart(s), rest.isEmpty else { return nil }
        return n
    }

    /// `Display for Number`.
    public var display: String {
        let abs = Swift.abs(number)
        let digits: UInt8 = abs < 1.0 ? 0 : floorLog(abs) &+ 1
        if significantFigures < digits {
            let shift = powi10(Int32(digits - significantFigures))
            let n = (Double(number) / shift).rounded(.toNearestOrAwayFromZero) * shift
            return rustFormatFixed(n, decimals: 0)
        }
        return rustFormatFixed(Double(number), decimals: Int(significantFigures - digits))
    }

    public func muvJSON() -> MuvJSON { .string(display) }

    // Arithmetic, the significant figures the fewer of the two.

    static func * (a: Number, b: Number) -> Number {
        Number(number: a.number * b.number, significantFigures: min(a.significantFigures, b.significantFigures))
    }

    static func / (a: Number, b: Number) -> Number {
        let q = a.number / b.number
        precondition(!q.isNaN, "division by 0")
        return Number(number: q, significantFigures: min(a.significantFigures, b.significantFigures))
    }

    static func + (a: Number, b: Number) -> Number {
        Number(number: a.number + b.number, significantFigures: min(a.significantFigures, b.significantFigures))
    }

    static func - (a: Number, b: Number) -> Number {
        Number(number: a.number - b.number, significantFigures: min(a.significantFigures, b.significantFigures))
    }

    /// `PartialEq for Number`: the same value, and the same figures unless infinite.
    public static func == (a: Number, b: Number) -> Bool {
        a.number == b.number
            && (a.significantFigures == b.significantFigures || a.number.isInfinite || b.number.isInfinite)
    }

    /// `Ord for Number`: by value, then by significant figures (-1, 0 or 1).
    static func cmp(_ a: Number, _ b: Number) -> Int {
        if a.number != b.number { return a.number < b.number ? -1 : 1 }
        return a.significantFigures == b.significantFigures ? 0 : (a.significantFigures < b.significantFigures ? -1 : 1)
    }
}

extension UInt8 {
    func saturatingAdd(_ o: UInt8) -> UInt8 {
        let (r, overflow) = addingReportingOverflow(o)
        return overflow ? .max : r
    }
}

/// `n.log10() as u8` on an `f32`: the system's `log10f`, saturated into `u8`.
private func floorLog(_ n: Float) -> UInt8 {
    let l = log10f(n)
    if l.isNaN || l <= 0 { return 0 }
    if l >= 255 { return 255 }
    return UInt8(l)
}

/// `10f64.powi(e)`: compiler-rt's `__powidf2`, repeated squaring.
private func powi10(_ e: Int32) -> Double {
    var a = 10.0, b = e, r = 1.0
    let recip = b < 0
    while true {
        if b & 1 != 0 { r *= a }
        b /= 2
        if b == 0 { break }
        a *= a
    }
    return recip ? 1 / r : r
}

/// Rust's `{:.N}` for a float: the exact decimal value rounded half to
/// even, as the C library's `%.*f` also writes it, and `inf` for infinity.
func rustFormatFixed(_ x: Double, decimals: Int) -> String {
    if x.isInfinite { return x < 0 ? "-inf" : "inf" }
    // At most 309 digits before the point and 255 after it.
    var buffer = [CChar](repeating: 0, count: 640)
    let n = withVaList([Int32(decimals), x]) { vsnprintf(&buffer, buffer.count, "%.*f", $0) }
    return String(decoding: buffer[..<Int(n)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
