/// A JSON value as serde_json's `Value` holds it (objects as a map sorted by
/// key, since the `preserve_order` feature is off), and its pretty printer,
/// byte for byte as `serde_json::to_string_pretty` writes it.

public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    /// Keys are kept sorted by their UTF-8 bytes when written, as a Rust `BTreeMap<String, _>`.
    case object([String: JSONValue])

    /// An object whose keys are written in the given order (for structs that
    /// serde serialises field by field).
    case orderedObject([(String, JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        a.prettyString() == b.prettyString()
    }
}

/// Rust's `Ord` for `String`: byte-wise on UTF-8.
@inlinable
public func rustStringLess(_ a: String, _ b: String) -> Bool {
    a.utf8.lexicographicallyPrecedes(b.utf8)
}

extension JSONValue {
    /// `serde_json::to_string_pretty`: two-space indent, `": "` after keys,
    /// empty arrays and objects as `[]` and `{}`.
    public func prettyString() -> String {
        var out: [UInt8] = []
        out.reserveCapacity(1024)
        write(into: &out, indent: 0)
        return String(decoding: out, as: UTF8.self)
    }

    func write(into out: inout [UInt8], indent: Int) {
        switch self {
        case .null: out.append(contentsOf: "null".utf8)
        case .bool(let b): out.append(contentsOf: (b ? "true" : "false").utf8)
        case .int(let i): out.append(contentsOf: String(i).utf8)
        case .uint(let u): out.append(contentsOf: String(u).utf8)
        case .double(let d): out.append(contentsOf: serdeJSONNumber(d).utf8)
        case .string(let s): writeJSONString(s, into: &out)
        case .array(let items):
            if items.isEmpty { out.append(contentsOf: "[]".utf8); return }
            out.append(UInt8(ascii: "["))
            for (i, item) in items.enumerated() {
                out.append(contentsOf: (i == 0 ? "\n" : ",\n").utf8)
                writeIndent(indent + 1, into: &out)
                item.write(into: &out, indent: indent + 1)
            }
            out.append(UInt8(ascii: "\n"))
            writeIndent(indent, into: &out)
            out.append(UInt8(ascii: "]"))
        case .object(let map):
            let keys = map.keys.sorted(by: rustStringLess)
            writeObject(keys.map { ($0, map[$0]!) }, into: &out, indent: indent)
        case .orderedObject(let pairs):
            writeObject(pairs, into: &out, indent: indent)
        }
    }

    private func writeObject(_ pairs: [(String, JSONValue)], into out: inout [UInt8], indent: Int) {
        if pairs.isEmpty { out.append(contentsOf: "{}".utf8); return }
        out.append(UInt8(ascii: "{"))
        for (i, (k, v)) in pairs.enumerated() {
            out.append(contentsOf: (i == 0 ? "\n" : ",\n").utf8)
            writeIndent(indent + 1, into: &out)
            writeJSONString(k, into: &out)
            out.append(contentsOf: ": ".utf8)
            v.write(into: &out, indent: indent + 1)
        }
        out.append(UInt8(ascii: "\n"))
        writeIndent(indent, into: &out)
        out.append(UInt8(ascii: "}"))
    }
}

private func writeIndent(_ n: Int, into out: inout [UInt8]) {
    for _ in 0..<n { out.append(0x20); out.append(0x20) }
}

/// serde_json's string escaping: `"`, `\`, and control characters (as `\b`,
/// `\f`, `\n`, `\r`, `\t` or `\u00XX`). Everything else is written as UTF-8.
func writeJSONString(_ s: String, into out: inout [UInt8]) {
    out.append(UInt8(ascii: "\""))
    let hex = Array("0123456789abcdef".utf8)
    for b in s.utf8 {
        switch b {
        case UInt8(ascii: "\""): out.append(contentsOf: "\\\"".utf8)
        case UInt8(ascii: "\\"): out.append(contentsOf: "\\\\".utf8)
        case 0x08: out.append(contentsOf: "\\b".utf8)
        case 0x0C: out.append(contentsOf: "\\f".utf8)
        case 0x0A: out.append(contentsOf: "\\n".utf8)
        case 0x0D: out.append(contentsOf: "\\r".utf8)
        case 0x09: out.append(contentsOf: "\\t".utf8)
        case 0x00..<0x20:
            out.append(contentsOf: "\\u00".utf8)
            out.append(hex[Int(b >> 4)])
            out.append(hex[Int(b & 0xF)])
        default: out.append(b)
        }
    }
    out.append(UInt8(ascii: "\""))
}
