/// A small JSON reader for GeoJSON inputs (the clip polygon). Numbers are
/// parsed from their text with `Double(_:)`, which rounds correctly as
/// serde_json does.

public enum JSONParseError: Error {
    case unexpected(String, at: Int)
}

extension JSONValue {
    public static func parse(_ text: String) throws -> JSONValue {
        var p = JSONReader(bytes: Array(text.utf8))
        let v = try p.value()
        p.skipSpace()
        if p.i != p.bytes.count { throw JSONParseError.unexpected("trailing characters", at: p.i) }
        return v
    }

    public subscript(key: String) -> JSONValue? {
        switch self {
        case .object(let m): return m[key]
        case .orderedObject(let pairs): return pairs.first { $0.0 == key }?.1
        default: return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .uint(let u): return Double(u)
        default: return nil
        }
    }
}

private struct JSONReader {
    let bytes: [UInt8]
    var i = 0

    mutating func skipSpace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func value() throws -> JSONValue {
        skipSpace()
        guard i < bytes.count else { throw JSONParseError.unexpected("end of input", at: i) }
        switch bytes[i] {
        case UInt8(ascii: "{"):
            i += 1
            var map: [String: JSONValue] = [:]
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(map) }
            while true {
                skipSpace()
                guard case .string(let key) = try value() else { throw JSONParseError.unexpected("key", at: i) }
                skipSpace()
                try expect(":")
                map[key] = try value()
                skipSpace()
                if try commaOrEnd("}") { return .object(map) }
            }
        case UInt8(ascii: "["):
            i += 1
            var items: [JSONValue] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            while true {
                items.append(try value())
                skipSpace()
                if try commaOrEnd("]") { return .array(items) }
            }
        case UInt8(ascii: "\""):
            return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default:
            return try number()
        }
    }

    mutating func expect(_ c: Unicode.Scalar) throws {
        guard i < bytes.count, bytes[i] == UInt8(ascii: c) else { throw JSONParseError.unexpected("\(c)", at: i) }
        i += 1
    }

    mutating func commaOrEnd(_ end: Unicode.Scalar) throws -> Bool {
        guard i < bytes.count else { throw JSONParseError.unexpected("end of input", at: i) }
        if bytes[i] == UInt8(ascii: ",") { i += 1; return false }
        try expect(end)
        return true
    }

    mutating func literal(_ word: String) throws {
        for c in word.utf8 {
            guard i < bytes.count, bytes[i] == c else { throw JSONParseError.unexpected(word, at: i) }
            i += 1
        }
    }

    // Numbers are read as serde_json 1.0 reads them without its
    // `float_roundtrip` feature: the digits into a u64 (ignoring digits past
    // its range), then one multiplication or division by a power of ten.
    // That is not always correctly rounded, and osm2streets reads its clip
    // polygon this way.

    private func peekByte() -> UInt8 { i < bytes.count ? bytes[i] : 0 }

    private func isDigit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }

    private func overflows(_ a: UInt64, _ digit: UInt64) -> Bool {
        a >= UInt64.max / 10 && (a > UInt64.max / 10 || digit > UInt64.max % 10)
    }

    mutating func number() throws -> JSONValue {
        let start = i
        var positive = true
        if peekByte() == UInt8(ascii: "-") {
            positive = false
            i += 1
        }
        guard i < bytes.count else { throw JSONParseError.unexpected("number", at: start) }
        let first = bytes[i]
        i += 1
        if first == UInt8(ascii: "0") {
            if isDigit(peekByte()) { throw JSONParseError.unexpected("number", at: start) }
            return try afterInteger(positive, 0)
        }
        guard first >= UInt8(ascii: "1") && first <= UInt8(ascii: "9") else {
            throw JSONParseError.unexpected("number", at: start)
        }
        var significand = UInt64(first - UInt8(ascii: "0"))
        while isDigit(peekByte()) {
            let digit = UInt64(peekByte() - UInt8(ascii: "0"))
            if overflows(significand, digit) { return .double(try longInteger(positive, significand)) }
            i += 1
            significand = significand * 10 + digit
        }
        return try afterInteger(positive, significand)
    }

    private mutating func afterInteger(_ positive: Bool, _ significand: UInt64) throws -> JSONValue {
        switch peekByte() {
        case UInt8(ascii: "."): return .double(try decimal(positive, significand, 0))
        case UInt8(ascii: "e"), UInt8(ascii: "E"): return .double(try exponent(positive, significand, 0))
        default:
            if positive { return .uint(significand) }
            let neg = Int64(bitPattern: significand) &* -1
            if neg >= 0 { return .double(-Double(significand)) }
            return .int(neg)
        }
    }

    private mutating func longInteger(_ positive: Bool, _ significand: UInt64) throws -> Double {
        var exp: Int32 = 0
        while true {
            switch peekByte() {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                i += 1
                exp += 1
            case UInt8(ascii: "."): return try decimal(positive, significand, exp)
            case UInt8(ascii: "e"), UInt8(ascii: "E"): return try exponent(positive, significand, exp)
            default: return try f64FromParts(positive, significand, exp)
            }
        }
    }

    private mutating func decimal(_ positive: Bool, _ significand: UInt64, _ exponentBefore: Int32) throws -> Double {
        i += 1
        var significand = significand
        var exponentAfter: Int32 = 0
        while isDigit(peekByte()) {
            let digit = UInt64(peekByte() - UInt8(ascii: "0"))
            if overflows(significand, digit) {
                while isDigit(peekByte()) { i += 1 }
                let e = exponentBefore + exponentAfter
                if peekByte() == UInt8(ascii: "e") || peekByte() == UInt8(ascii: "E") {
                    return try exponent(positive, significand, e)
                }
                return try f64FromParts(positive, significand, e)
            }
            i += 1
            significand = significand * 10 + digit
            exponentAfter -= 1
        }
        if exponentAfter == 0 { throw JSONParseError.unexpected("digit after the point", at: i) }
        let e = exponentBefore + exponentAfter
        if peekByte() == UInt8(ascii: "e") || peekByte() == UInt8(ascii: "E") {
            return try exponent(positive, significand, e)
        }
        return try f64FromParts(positive, significand, e)
    }

    private mutating func exponent(_ positive: Bool, _ significand: UInt64, _ startingExp: Int32) throws -> Double {
        i += 1
        var positiveExp = true
        if peekByte() == UInt8(ascii: "+") {
            i += 1
        } else if peekByte() == UInt8(ascii: "-") {
            positiveExp = false
            i += 1
        }
        guard isDigit(peekByte()) else { throw JSONParseError.unexpected("exponent", at: i) }
        var exp = Int32(peekByte() - UInt8(ascii: "0"))
        i += 1
        while isDigit(peekByte()) {
            let digit = Int32(peekByte() - UInt8(ascii: "0"))
            i += 1
            if exp >= Int32.max / 10 && (exp > Int32.max / 10 || digit > Int32.max % 10) {
                if significand != 0 && positiveExp { throw JSONParseError.unexpected("number out of range", at: i) }
                while isDigit(peekByte()) { i += 1 }
                return positive ? 0.0 : -0.0
            }
            exp = exp * 10 + digit
        }
        let (sum, o1) = startingExp.addingReportingOverflow(exp)
        let (diff, o2) = startingExp.subtractingReportingOverflow(exp)
        let finalExp = positiveExp ? (o1 ? Int32.max : sum) : (o2 ? Int32.min : diff)
        return try f64FromParts(positive, significand, finalExp)
    }

    private func f64FromParts(_ positive: Bool, _ significand: UInt64, _ exponent: Int32) throws -> Double {
        var f = Double(significand)
        var exponent = exponent
        while true {
            let index = Int(exponent == Int32.min ? Int32.min : (exponent < 0 ? -exponent : exponent))
            if index >= 0 && index < 309 {
                let pow = serdePow10[index]
                if exponent >= 0 {
                    f *= pow
                    if f.isInfinite { throw JSONParseError.unexpected("number out of range", at: i) }
                } else {
                    f /= pow
                }
                break
            }
            if f == 0.0 { break }
            if exponent >= 0 { throw JSONParseError.unexpected("number out of range", at: i) }
            f /= 1e308
            exponent += 308
        }
        return positive ? f : -f
    }

    mutating func string() throws -> String {
        try expect("\"")
        var out: [UInt8] = []
        while i < bytes.count {
            let c = bytes[i]
            i += 1
            if c == UInt8(ascii: "\"") { return String(decoding: out, as: UTF8.self) }
            if c != UInt8(ascii: "\\") { out.append(c); continue }
            guard i < bytes.count else { break }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "u"):
                var code = try hex4()
                if (0xD800..<0xDC00).contains(code), i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\") {
                    i += 2
                    let low = try hex4()
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                }
                out.append(contentsOf: Array(String(Character(Unicode.Scalar(code) ?? "?")).utf8))
            default: out.append(e)
            }
        }
        throw JSONParseError.unexpected("unterminated string", at: i)
    }

    mutating func hex4() throws -> UInt32 {
        guard i + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[i..<(i + 4)], as: UTF8.self), radix: 16) else {
            throw JSONParseError.unexpected("\\u escape", at: i)
        }
        i += 4
        return v
    }
}

/// serde_json's `POW10`: 1e0 to 1e308, each correctly rounded.
let serdePow10: [Double] = (0...308).map { Double("1e\($0)")! }
