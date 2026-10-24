/// A small XML reader for OSM files: the document's elements, their
/// attributes and children, in document order. It stands in for roxmltree,
/// which osm-reader parses with, and keeps what osm-reader reads of it:
/// element names, attribute values (entities decoded and whitespace
/// normalised as XML requires) and the parent-child structure. Text, comments,
/// processing instructions, CDATA and the document type are skipped.

/// One element of the document.
struct XMLElement {
    var name: String
    var attributes: [(String, String)]
    var children: [Int] = []

    func attribute(_ key: String) -> String? {
        for (k, v) in attributes where k == key { return v }
        return nil
    }
}

/// The elements of a document, in the order their start tags appear (the
/// order of roxmltree's `descendants`).
struct XMLTree {
    private(set) var elements: [XMLElement] = []

    init(_ bytes: [UInt8]) throws {
        var scanner = Scanner(bytes: bytes)
        var stack: [Int] = []
        while let event = try scanner.next() {
            switch event {
            case .start(let name, let attributes, let selfClosing):
                let index = elements.count
                elements.append(XMLElement(name: name, attributes: attributes))
                if let parent = stack.last { elements[parent].children.append(index) }
                if !selfClosing { stack.append(index) }
            case .end(let name):
                guard let open = stack.popLast(), elements[open].name == name else {
                    throw OSMReaderError.malformedXML("unexpected </\(name)>")
                }
            }
        }
        if !stack.isEmpty { throw OSMReaderError.malformedXML("unclosed <\(elements[stack.last!].name)>") }
        if elements.isEmpty { throw OSMReaderError.malformedXML("no root element") }
    }
}

/// The tokenizer: start and end tags, everything else skipped.
private struct Scanner {
    enum Event {
        case start(String, [(String, String)], selfClosing: Bool)
        case end(String)
    }

    let bytes: [UInt8]
    var i = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func next() throws -> Event? {
        while i < bytes.count {
            if bytes[i] != UInt8(ascii: "<") { i += 1; continue }
            if starts(with: "<?") { try skip(past: "?>"); continue }
            if starts(with: "<!--") { try skip(past: "-->"); continue }
            if starts(with: "<![CDATA[") { try skip(past: "]]>"); continue }
            if starts(with: "<!") { try skipDeclaration(); continue }
            if starts(with: "</") {
                i += 2
                let name = readName()
                skipSpace()
                try expect(">")
                return .end(name)
            }
            i += 1
            let name = readName()
            if name.isEmpty { throw OSMReaderError.malformedXML("empty element name at byte \(i)") }
            var attributes: [(String, String)] = []
            while true {
                skipSpace()
                guard i < bytes.count else { throw OSMReaderError.malformedXML("unexpected end of input") }
                if bytes[i] == UInt8(ascii: "/") {
                    i += 1
                    try expect(">")
                    return .start(name, attributes, selfClosing: true)
                }
                if bytes[i] == UInt8(ascii: ">") {
                    i += 1
                    return .start(name, attributes, selfClosing: false)
                }
                let key = readName()
                if key.isEmpty { throw OSMReaderError.malformedXML("bad attribute at byte \(i)") }
                skipSpace()
                try expect("=")
                skipSpace()
                let value = try readAttributeValue()
                if attributes.contains(where: { $0.0 == key }) {
                    throw OSMReaderError.malformedXML("duplicate attribute \(key)")
                }
                attributes.append((key, value))
            }
        }
        return nil
    }

    private func starts(with text: StaticString) -> Bool {
        let n = text.utf8CodeUnitCount
        if i + n > bytes.count { return false }
        let p = text.utf8Start
        for k in 0..<n where bytes[i + k] != p[k] { return false }
        return true
    }

    private mutating func skip(past text: StaticString) throws {
        while i < bytes.count {
            if starts(with: text) { i += text.utf8CodeUnitCount; return }
            i += 1
        }
        throw OSMReaderError.malformedXML("unterminated markup")
    }

    /// A `<!DOCTYPE ...>` with an optional internal subset in brackets.
    private mutating func skipDeclaration() throws {
        var depth = 0
        while i < bytes.count {
            let b = bytes[i]
            i += 1
            if b == UInt8(ascii: "[") { depth += 1 }
            if b == UInt8(ascii: "]") { depth -= 1 }
            if b == UInt8(ascii: ">") && depth <= 0 { return }
        }
        throw OSMReaderError.malformedXML("unterminated declaration")
    }

    private mutating func expect(_ c: Unicode.Scalar) throws {
        guard i < bytes.count, bytes[i] == UInt8(ascii: c) else {
            throw OSMReaderError.malformedXML("expected \(c) at byte \(i)")
        }
        i += 1
    }

    private mutating func skipSpace() {
        while i < bytes.count, isSpace(bytes[i]) { i += 1 }
    }

    private func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    private mutating func readName() -> String {
        let start = i
        while i < bytes.count {
            let b = bytes[i]
            if isSpace(b) || b == UInt8(ascii: "/") || b == UInt8(ascii: ">") || b == UInt8(ascii: "=") { break }
            i += 1
        }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    /// A quoted value: line ends normalised, then every whitespace character
    /// becomes a space, then character and entity references decoded (the
    /// characters they produce are kept as they are).
    private mutating func readAttributeValue() throws -> String {
        guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") || bytes[i] == UInt8(ascii: "'") else {
            throw OSMReaderError.malformedXML("expected a quoted value at byte \(i)")
        }
        let quote = bytes[i]
        i += 1
        var out: [UInt8] = []
        while i < bytes.count, bytes[i] != quote {
            let b = bytes[i]
            if b == UInt8(ascii: "&") {
                try decodeReference(into: &out)
                continue
            }
            if b == UInt8(ascii: "<") { throw OSMReaderError.malformedXML("< in an attribute value") }
            if b == 0x0D {
                // \r\n and a lone \r are one line end, which becomes one space.
                if i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 1 }
                out.append(0x20)
            } else if b == 0x0A || b == 0x09 {
                out.append(0x20)
            } else {
                out.append(b)
            }
            i += 1
        }
        guard i < bytes.count else { throw OSMReaderError.malformedXML("unterminated attribute value") }
        i += 1
        guard let text = String(validating: out, as: UTF8.self) else { throw OSMReaderError.notUTF8 }
        return text
    }

    private mutating func decodeReference(into out: inout [UInt8]) throws {
        let start = i + 1
        var end = start
        while end < bytes.count, bytes[end] != UInt8(ascii: ";") {
            end += 1
            if end - start > 12 { throw OSMReaderError.malformedXML("bad reference at byte \(i)") }
        }
        guard end < bytes.count else { throw OSMReaderError.malformedXML("unterminated reference") }
        let name = String(decoding: bytes[start..<end], as: UTF8.self)
        i = end + 1
        let scalar: Unicode.Scalar?
        switch name {
        case "amp": scalar = "&"
        case "lt": scalar = "<"
        case "gt": scalar = ">"
        case "quot": scalar = "\""
        case "apos": scalar = "'"
        default:
            if name.hasPrefix("#x") {
                scalar = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init)
            } else if name.hasPrefix("#") {
                scalar = UInt32(name.dropFirst(1), radix: 10).flatMap(Unicode.Scalar.init)
            } else {
                scalar = nil
            }
        }
        guard let scalar else { throw OSMReaderError.malformedXML("unknown reference &\(name);") }
        out.append(contentsOf: Array(String(Character(scalar)).utf8))
    }
}
