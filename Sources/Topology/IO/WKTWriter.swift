import Foundation

/// Writes Well-Known Text, in JTS's layout (`POINT (1 2)`, `POLYGON ((...), (...))`,
/// `MULTIPOINT ((1 2), (3 4))`, `POINT EMPTY`).
///
/// Numbers: without a rounding precision, the shortest text that reads back
/// as the same double, in plain notation. With one (`roundingPrecision: 3`),
/// as GEOS 3.13's writer with that rounding precision writes them (its
/// trimmed numbers, matched on GEOS's output): see `trimmed`.
public struct WKTWriter {
    public var roundingPrecision: Int?

    public init(roundingPrecision: Int? = nil) { self.roundingPrecision = roundingPrecision }

    public func write(_ g: Geometry) -> String {
        var s = ""
        append(g, to: &s)
        return s
    }

    func append(_ g: Geometry, to s: inout String) {
        s += g.getGeometryType().uppercased()
        if g.isEmpty() {
            s += " EMPTY"
            return
        }
        s += " "
        body(g, &s)
    }

    func body(_ g: Geometry, _ s: inout String) {
        switch g {
        case let p as Point:
            s += "(" + coordinate(p.coordinates[0]) + ")"
        case let l as LineString:
            s += sequence(l.points)
        case let p as Polygon:
            s += "(" + ([p.shell] + p.holes).map { sequence($0.points) }.joined(separator: ", ") + ")"
        case let m as MultiPoint:
            s += "(" + m.geometries.map { $0.isEmpty() ? "EMPTY" : "(" + coordinate($0.getCoordinate()!) + ")" }
                .joined(separator: ", ") + ")"
        case let m as MultiLineString:
            s += "(" + m.geometries.map { sequence(($0 as! LineString).points) }.joined(separator: ", ") + ")"
        case let m as MultiPolygon:
            s += "(" + m.geometries.map { member in
                var t = ""
                if member.isEmpty() { t = "EMPTY" } else { body(member, &t) }
                return t
            }.joined(separator: ", ") + ")"
        case let c as GeometryCollection:
            s += "(" + c.geometries.map { write($0) }.joined(separator: ", ") + ")"
        default:
            break
        }
    }

    func sequence(_ pts: [Coordinate]) -> String {
        if pts.isEmpty { return "EMPTY" }
        return "(" + pts.map(coordinate).joined(separator: ", ") + ")"
    }

    func coordinate(_ c: Coordinate) -> String { number(c.x) + " " + number(c.y) }

    public func number(_ d: Double) -> String {
        guard let p = roundingPrecision, p >= 0 else {
            if d.isNaN { return "NaN" }
            if d.isInfinite { return d < 0 ? "-Inf" : "Inf" }
            return WKTWriter.plain(d)
        }
        // GEOS's writer (its copy of ryu): `NaN` whatever its sign,
        // `Infinity` and `-Infinity`.
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        return WKTWriter.trimmed(d, p)
    }

    /// A number as GEOS writes it with a rounding precision: zero as `0`;
    /// from 1e17 and below 1e-4 in scientific notation with `precision`
    /// decimals (`9.99e-5`, `1.235e+20`); else in positional notation with
    /// `precision` decimals, or, below 1 and for a precision under 4, as many
    /// as keep the first significant digit (`0.2` for 0.218). The shortest
    /// digits of the double are rounded half to even (0.35 gives 0.4, 0.25
    /// gives 0.2), and trailing zeros trimmed.
    static func trimmed(_ d: Double, _ precision: Int) -> String {
        let da = abs(d)
        if da == 0 { return "0" }
        let (negative, shortest, exponent10) = decimalDigits(d)
        var digits = shortest, point = exponent10
        if da >= 1e17 || da < 1e-4 {
            // Scientific: one digit before the point.
            var exponent = point - 1
            var kept = round(digits, precision + 1)
            if kept.count > precision + 1 {
                kept.removeLast()
                exponent += 1
            }
            var mantissa = String(kept[0])
            let rest = kept.dropFirst().map(String.init).joined()
            if !rest.isEmpty { mantissa += "." + rest }
            if mantissa.contains(".") {
                while mantissa.hasSuffix("0") { mantissa.removeLast() }
                if mantissa.hasSuffix(".") { mantissa.removeLast() }
            }
            return (negative ? "-" : "") + mantissa + "e" + (exponent < 0 ? "-" : "+") + String(abs(exponent))
        }
        var decimals = precision
        if precision < 4 && da < 1.0 { decimals = Int(-(log10(da)).rounded(.down)) }
        // Keep the digits up to `decimals` after the point: at least the
        // first, since the decimals reach the first significant digit.
        let keep = point + decimals
        if keep <= 0 { return "0" }
        digits = round(digits, keep)
        if digits.count > keep { point += 1 }
        var intPart = "", fracPart = ""
        for (i, dg) in digits.enumerated() {
            if i < point { intPart += String(dg) } else { fracPart += String(dg) }
        }
        if point > digits.count { intPart += String(repeating: "0", count: point - digits.count) }
        if point < 0 { fracPart = String(repeating: "0", count: -point) + fracPart }
        if intPart.isEmpty { intPart = "0" }
        while fracPart.hasSuffix("0") { fracPart.removeLast() }
        let text = fracPart.isEmpty ? intPart : intPart + "." + fracPart
        if text == "0" { return "0" }
        return (negative ? "-" : "") + text
    }

    /// The shortest round-trip digits of a double and the place of the
    /// decimal point: the value is 0.d1d2d3... times ten to the `point`.
    static func decimalDigits(_ d: Double) -> (Bool, [Int], Int) {
        let s = "\(abs(d))"
        var mantissa = Substring(s), exponent = 0
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = s[..<e]
            exponent = Int(s[s.index(after: e)...])!
        }
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let intDigits = Array(parts[0]), fracDigits = parts.count > 1 ? Array(parts[1]) : []
        var digits = (intDigits + fracDigits).map { Int(String($0))! }
        var point = intDigits.count + exponent
        while digits.first == 0 && digits.count > 1 {
            digits.removeFirst()
            point -= 1
        }
        while digits.last == 0 && digits.count > 1 { digits.removeLast() }
        return (d.sign == .minus, digits, point)
    }

    /// The first `n` digits, rounded half to even by the rest, with one more
    /// digit when the rounding carries out (`999` to `1000`).
    static func round(_ digits: [Int], _ n: Int) -> [Int] {
        if digits.count <= n { return digits + [Int](repeating: 0, count: n - digits.count) }
        var kept = Array(digits[..<n])
        let next = digits[n], tail = digits[(n + 1)...].contains { $0 != 0 }
        let up = next > 5 || (next == 5 && (tail || (kept.last ?? 0) % 2 == 1))
        if up {
            var i = kept.count - 1
            while i >= 0 {
                kept[i] += 1
                if kept[i] < 10 { break }
                kept[i] = 0
                i -= 1
            }
            if i < 0 { kept.insert(1, at: 0) }
        }
        return kept
    }

    /// The shortest round-trip digits of a double, in plain notation.
    static func plain(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        let s = "\(d)"
        guard let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return s }
        // Swift writes 1e-07 or 1.5e+20: spell it out.
        let mantissa = s[..<e], exponent = Int(s[s.index(after: e)...])!
        let negative = mantissa.hasPrefix("-")
        let digits = mantissa.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "")
        let point = (mantissa.replacingOccurrences(of: "-", with: "").firstIndex(of: ".").map {
            mantissa.replacingOccurrences(of: "-", with: "").distance(from: mantissa.replacingOccurrences(of: "-", with: "").startIndex, to: $0)
        } ?? digits.count) + exponent
        var out: String
        if point <= 0 {
            out = "0." + String(repeating: "0", count: -point) + digits
        } else if point >= digits.count {
            out = digits + String(repeating: "0", count: point - digits.count)
        } else {
            out = String(digits.prefix(point)) + "." + String(digits.dropFirst(point))
        }
        return negative ? "-" + out : out
    }
}
