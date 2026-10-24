/// Reads Well-Known Text: JTS's `WKTReader`, with its tolerances (the old JTS
/// syntax of a third ordinate without a `Z` and of multipoints without
/// parentheses around each point, text after the geometry ignored). Only x
/// and y are kept, made precise to the factory's precision model.
public struct WKTReader {
    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
    }

    let factory: GeometryFactory

    public init(_ factory: GeometryFactory = .default) { self.factory = factory }

    public func read(_ text: String) throws -> Geometry {
        var t = Tokenizer(Array(text.utf8))
        let type = try t.word().uppercased()
        return try readTagged(&t, type)
    }

    // MARK: Tokens

    enum Token: Equatable {
        case word(String), open, close, comma, end
    }

    struct Tokenizer {
        let bytes: [UInt8]
        var at = 0
        var pushed: Token?

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        static func isWordChar(_ c: UInt8) -> Bool {
            (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 || c >= 160
        }

        mutating func next() -> Token {
            if let p = pushed {
                pushed = nil
                return p
            }
            while at < bytes.count {
                let c = bytes[at]
                if c <= 32 {
                    at += 1
                } else if c == 35 {
                    // A comment to the end of the line.
                    while at < bytes.count && bytes[at] != 10 && bytes[at] != 13 { at += 1 }
                } else {
                    break
                }
            }
            guard at < bytes.count else { return .end }
            let c = bytes[at]
            at += 1
            switch c {
            case 40: return .open
            case 41: return .close
            case 44: return .comma
            default:
                guard Tokenizer.isWordChar(c) else { return .word(String(UnicodeScalar(c))) }
                let start = at - 1
                while at < bytes.count && Tokenizer.isWordChar(bytes[at]) { at += 1 }
                return .word(String(decoding: bytes[start..<at], as: UTF8.self))
            }
        }

        mutating func pushBack(_ t: Token) { pushed = t }

        mutating func peek() -> Token {
            let t = next()
            pushBack(t)
            return t
        }

        mutating func word() throws -> String {
            switch next() {
            case .word(let w): return w.uppercased() == "EMPTY" ? "EMPTY" : w
            case .open: return "("
            case .close: return ")"
            case .comma: return ","
            case .end: throw ParseError(description: "Expected word but found End-of-Stream")
            }
        }

        mutating func number() throws -> Double {
            guard case .word(let w) = next() else { throw ParseError(description: "Expected number") }
            if w.lowercased() == "nan" { return .nan }
            guard let d = Double(w) else { throw ParseError(description: "Invalid number: \(w)") }
            return d
        }

        mutating func emptyOrOpener() throws -> Bool {
            var w = try word()
            if ["Z", "M", "ZM"].contains(w.uppercased()) { w = try word() }
            if w == "EMPTY" { return true }
            if w == "(" { return false }
            throw ParseError(description: "Expected EMPTY or ( but found '\(w)'")
        }

        mutating func closerOrComma() throws -> Bool {
            let w = try word()
            if w == "," { return true }
            if w == ")" { return false }
            throw ParseError(description: "Expected , or ) but found '\(w)'")
        }

        var isNumberNext: Bool {
            mutating get {
                if case .word = peek() { return true }
                return false
            }
        }
    }

    // MARK: Grammar

    struct Ordinates {
        var z = false, m = false
        var count: Int { 2 + (z ? 1 : 0) + (m ? 1 : 0) }
    }

    func readTagged(_ t: inout Tokenizer, _ type: String) throws -> Geometry {
        var ords = Ordinates()
        if type.hasSuffix("ZM") { ords.z = true; ords.m = true } else if type.hasSuffix("Z") { ords.z = true } else if type.hasSuffix("M") { ords.m = true }
        if ords.count == 2, case .word(let w) = t.peek() {
            switch w.uppercased() {
            case "Z": _ = t.next(); ords.z = true
            case "M": _ = t.next(); ords.m = true
            case "ZM": _ = t.next(); ords.z = true; ords.m = true
            default: break
            }
        }
        func isType(_ name: String) throws -> Bool {
            guard type.hasPrefix(name) else { return false }
            let mods = type.dropFirst(name.count)
            guard ["", "Z", "M", "ZM"].contains(String(mods)) else {
                throw ParseError(description: "Invalid dimension modifiers: \(type)")
            }
            return true
        }
        if try isType("POINT") { return try readPoint(&t, ords) }
        if try isType("LINESTRING") { return try line(try sequence(&t, ords)) }
        if try isType("LINEARRING") { return try ring(try sequence(&t, ords)) }
        if try isType("POLYGON") { return try readPolygon(&t, ords) }
        if try isType("MULTIPOINT") { return try readMultiPoint(&t, ords) }
        if try isType("MULTILINESTRING") {
            if try t.emptyOrOpener() { return factory.createMultiLineString() }
            var lines: [LineString] = []
            repeat { lines.append(try line(try sequence(&t, ords))) } while try t.closerOrComma()
            return factory.createMultiLineString(lines)
        }
        if try isType("MULTIPOLYGON") {
            if try t.emptyOrOpener() { return factory.createMultiPolygon() }
            var polys: [Polygon] = []
            repeat { polys.append(try readPolygon(&t, ords)) } while try t.closerOrComma()
            return factory.createMultiPolygon(polys)
        }
        if try isType("GEOMETRYCOLLECTION") {
            if try t.emptyOrOpener() { return factory.createGeometryCollection() }
            var geoms: [Geometry] = []
            repeat { geoms.append(try readTagged(&t, try t.word().uppercased())) } while try t.closerOrComma()
            return factory.createGeometryCollection(geoms)
        }
        throw ParseError(description: "Unknown geometry type: \(type)")
    }

    func coordinate(_ t: inout Tokenizer, _ ords: Ordinates, tryParen: Bool) throws -> Coordinate {
        var opened = false
        if tryParen && t.peek() == .open {
            _ = t.next()
            opened = true
        }
        let x = factory.precisionModel.makePrecise(try t.number())
        let y = factory.precisionModel.makePrecise(try t.number())
        if ords.z { _ = try t.number() }
        if ords.m { _ = try t.number() }
        // The old JTS syntax: a third ordinate without a Z.
        if ords.count == 2 && t.isNumberNext { _ = try t.number() }
        if opened {
            guard try t.word() == ")" else { throw ParseError(description: "Expected )") }
        }
        return Coordinate(x, y)
    }

    func sequence(_ t: inout Tokenizer, _ ords: Ordinates) throws -> [Coordinate] {
        if try t.emptyOrOpener() { return [] }
        var c: [Coordinate] = []
        repeat { c.append(try coordinate(&t, ords, tryParen: false)) } while try t.closerOrComma()
        return c
    }

    func readPoint(_ t: inout Tokenizer, _ ords: Ordinates) throws -> Point {
        let c = try sequence(&t, ords)
        guard c.count <= 1 else { throw ParseError(description: "A point has one coordinate") }
        return factory.createPoint(c)
    }

    /// A line, refused as JTS's constructor refuses it.
    func line(_ c: [Coordinate]) throws -> LineString {
        guard c.isEmpty || c.count >= LineString.minimumValidSize else {
            throw ParseError(description: "Invalid number of points in LineString (found \(c.count) - must be 0 or >= 2)")
        }
        return factory.createLineString(c)
    }

    /// A ring, refused as JTS's constructor refuses it.
    func ring(_ c: [Coordinate]) throws -> LinearRing {
        guard c.isEmpty || c.first! == c.last! else {
            throw ParseError(description: "Points of LinearRing do not form a closed linestring")
        }
        guard c.isEmpty || c.count >= LinearRing.minimumValidRingSize else {
            throw ParseError(description: "Invalid number of points in LinearRing (found \(c.count) - must be 0 or >= 3)")
        }
        return factory.createLinearRing(c)
    }

    func readPolygon(_ t: inout Tokenizer, _ ords: Ordinates) throws -> Polygon {
        if try t.emptyOrOpener() { return factory.createPolygon() }
        let shell = try ring(try sequence(&t, ords))
        var holes: [LinearRing] = []
        while try t.closerOrComma() { holes.append(try ring(try sequence(&t, ords))) }
        return factory.createPolygon(shell, holes)
    }

    func readMultiPoint(_ t: inout Tokenizer, _ ords: Ordinates) throws -> MultiPoint {
        if try t.emptyOrOpener() { return factory.createMultiPoint() }
        let next = t.peek()
        if next != .open, case .word(let w) = next, w.uppercased() != "EMPTY" {
            var c: [Coordinate] = []
            repeat { c.append(try coordinate(&t, ords, tryParen: true)) } while try t.closerOrComma()
            return factory.createMultiPointFromCoords(c)
        }
        var points: [Point] = []
        repeat { points.append(try readPoint(&t, ords)) } while try t.closerOrComma()
        return factory.createMultiPoint(points)
    }
}
