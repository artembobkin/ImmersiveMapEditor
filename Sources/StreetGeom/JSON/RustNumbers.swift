/// How Rust prints an f64: serde_json's (ryu's) shortest round-trip form,
/// and the standard library's `Display` and `Debug`. Swift's `description`
/// already gives the shortest digits that round-trip, so these only lay the
/// digits out as Rust does.

/// The shortest round-trip decimal digits of a finite, non-zero magnitude,
/// and the exponent `k` such that the value is `digits * 10^k`.
struct ShortestDecimal {
    var digits: [UInt8]
    var exponent: Int

    init(_ magnitude: Double) {
        var text = Array("\(magnitude)".utf8)
        var exp10 = 0
        if let e = text.firstIndex(of: UInt8(ascii: "e")) {
            exp10 = Int(String(decoding: text[(e + 1)...], as: UTF8.self))!
            text = Array(text[..<e])
        }
        var digits: [UInt8] = []
        var pointSeen = false
        var fractional = 0
        for c in text {
            if c == UInt8(ascii: ".") { pointSeen = true; continue }
            digits.append(c - UInt8(ascii: "0"))
            if pointSeen { fractional += 1 }
        }
        var exponent = exp10 - fractional
        while digits.count > 1, digits.last == 0 { digits.removeLast(); exponent += 1 }
        while digits.count > 1, digits.first == 0 { digits.removeFirst() }
        self.digits = digits
        self.exponent = exponent
    }

    var string: String { String(decoding: digits.map { $0 + UInt8(ascii: "0") }, as: UTF8.self) }
}

/// serde_json's float: ryu's `format_finite`, `null` when not finite.
public func serdeJSONNumber(_ x: Double) -> String {
    guard x.isFinite else { return "null" }
    var out = x.sign == .minus ? "-" : ""
    if x == 0 { return out + "0.0" }
    let v = ShortestDecimal(Swift.abs(x))
    let length = v.digits.count
    let k = v.exponent
    let kk = length + k
    let m = v.string
    if 0 <= k && kk <= 16 {
        out += m + String(repeating: "0", count: kk - length) + ".0"
    } else if 0 < kk && kk <= 16 {
        let i = m.index(m.startIndex, offsetBy: kk)
        out += m[..<i] + "." + m[i...]
    } else if -5 < kk && kk <= 0 {
        out += "0." + String(repeating: "0", count: -kk) + m
    } else if length == 1 {
        out += m + "e" + String(kk - 1)
    } else {
        out += String(m.first!) + "." + m.dropFirst() + "e" + String(kk - 1)
    }
    return out
}

/// Rust's `Display` for f64: decimal notation always, no `.0` on whole numbers.
public func rustDisplay(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x < 0 ? "-inf" : "inf" }
    let sign = x.sign == .minus ? "-" : ""
    if x == 0 { return sign + "0" }
    let v = ShortestDecimal(Swift.abs(x))
    return sign + decimalLayout(v, forceFraction: false)
}

/// Rust's `Debug` for f64: as `Display` but with `.0` on whole numbers, and
/// scientific notation below 1e-4 and from 1e16.
public func rustDebugF64(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x < 0 ? "-inf" : "inf" }
    let sign = x.sign == .minus ? "-" : ""
    if x == 0 { return sign + "0.0" }
    let a = Swift.abs(x)
    let v = ShortestDecimal(a)
    if a < 1e-4 || a >= 1e16 {
        let m = v.string
        let e = v.digits.count - 1 + v.exponent
        let mantissa = m.count == 1 ? m : String(m.first!) + "." + m.dropFirst()
        return sign + mantissa + "e" + String(e)
    }
    return sign + decimalLayout(v, forceFraction: true)
}

private func decimalLayout(_ v: ShortestDecimal, forceFraction: Bool) -> String {
    let m = v.string
    let length = v.digits.count
    let kk = length + v.exponent
    if v.exponent >= 0 {
        return m + String(repeating: "0", count: v.exponent) + (forceFraction ? ".0" : "")
    }
    if kk > 0 {
        let i = m.index(m.startIndex, offsetBy: kk)
        return m[..<i] + "." + m[i...]
    }
    return "0." + String(repeating: "0", count: -kk) + m
}
