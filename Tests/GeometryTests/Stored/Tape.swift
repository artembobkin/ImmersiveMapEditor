import Foundation

/// GEOS 3.13's answers as the parity tests stored them, one tape per test
/// (Docs/PortingParity.md, "Phase 12"): GEOS is gone from the package, and
/// each test reads, in the order it asks, what GEOS answered when the test
/// ran against it. A tape is a file of entries in that order, compressed
/// (LZMA), little-endian:
///
/// - the eight bytes `GEOTAPE1`,
/// - entries, each a tag byte and its payload (`Tape.Tag`),
/// - the end: the tag `end`, the count of entries and the alignment digest.
///
/// A payload of bytes (a geometry, a list, a text) is kept whole up to the
/// tape's `limit` and as a 64-bit digest of its bytes above it, so the
/// fixtures in git stay small: a digest that matches is the same bytes, bit
/// for bit, but for a chance of one in 2^64. A result that may be compared
/// by value too (the sign of zeros, GEOS's own randomness) keeps the digest
/// of its value form beside it.
///
/// The alignment digest covers what each test asked, in order: the
/// operation, its parameters and the digest of every input. A test that
/// asks for anything else than what was stored (another seed, another
/// generator, an operation moved) fails at its end, not silently.
enum Tape {
    static let magic = Array("GEOTAPE1".utf8)

    enum Tag: UInt8 {
        case none = 0, falseValue = 1, trueValue = 2
        /// A failure: GEOS returned its error value. Its message follows as a string, or `none`.
        case failure = 3
        case double = 4
        case int = 5
        /// Bytes kept whole: a count, then the bytes.
        case bytes = 6
        /// Bytes as their digest (8 bytes).
        case digest = 7
        /// A text already on the tape, by its number.
        case stringRef = 8
        /// A new text: its count of bytes and its bytes, numbered next.
        case stringNew = 9
        /// A list of doubles: a count, then the doubles.
        case doubles = 10
        /// A geometry answer (`StoredGeometry`).
        case geometry = 11
        /// A list of integers: a count, then each as a zigzag varint.
        case ints = 12
        /// A result of the wrapper's replay (`Observation`).
        case observation = 13
        case end = 0xFF
    }
}

/// A 64-bit digest of bytes, words mixed by SplitMix64's finalizer (a
/// bijection, so nearby inputs scatter). Not cryptographic: the tapes guard
/// against chance, not against an adversary.
struct Digest {
    private(set) var value: UInt64 = 0x243F_6A88_85A3_08D3
    private var count: UInt64 = 0

    static func mix(_ x: UInt64) -> UInt64 {
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func add(_ w: UInt64) {
        value = Digest.mix(value ^ w) &+ 0x9E37_79B9_7F4A_7C15
        count &+= 1
    }

    mutating func add(_ d: Double) { add(d.bitPattern) }
    mutating func add(_ i: Int) { add(UInt64(bitPattern: Int64(i))) }

    mutating func add(_ s: String) {
        add(Array(s.utf8))
    }

    mutating func add(_ bytes: [UInt8]) {
        var i = 0
        while i + 8 <= bytes.count {
            var w: UInt64 = 0
            for k in 0..<8 { w |= UInt64(bytes[i + k]) << (8 * k) }
            add(w)
            i += 8
        }
        var w: UInt64 = 0
        for k in 0..<(bytes.count - i) { w |= UInt64(bytes[i + k]) << (8 * k) }
        add(w ^ (UInt64(bytes.count) << 56))
    }

    /// The final value, the number of words folded in.
    var final: UInt64 { Digest.mix(value ^ count) }

    static func of(_ bytes: [UInt8]) -> UInt64 {
        var d = Digest()
        d.add(bytes)
        return d.final
    }
}

/// Bytes being written, with the varints and doubles of the format.
struct ByteSink {
    var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }

    mutating func varint(_ v: UInt64) {
        var v = v
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }

    mutating func varint(_ v: Int) { varint(UInt64(v)) }
    mutating func zigzag(_ v: Int) { varint(UInt64(bitPattern: Int64((v << 1) ^ (v >> 63)))) }

    mutating func u64(_ v: UInt64) {
        for k in 0..<8 { bytes.append(UInt8((v >> (8 * k)) & 0xFF)) }
    }

    mutating func f64(_ v: Double) { u64(v.bitPattern) }

    mutating func data(_ b: [UInt8]) {
        varint(b.count)
        bytes.append(contentsOf: b)
    }
}

/// Bytes being read back.
struct ByteSource {
    let bytes: [UInt8]
    var at = 0

    struct Truncated: Error {}

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { at >= bytes.count }

    mutating func u8() throws -> UInt8 {
        guard at < bytes.count else { throw Truncated() }
        defer { at += 1 }
        return bytes[at]
    }

    mutating func varint() throws -> UInt64 {
        var v: UInt64 = 0, shift: UInt64 = 0
        while true {
            let b = try u8()
            v |= UInt64(b & 0x7F) << shift
            if b < 0x80 { return v }
            shift += 7
        }
    }

    mutating func count() throws -> Int { Int(try varint()) }

    mutating func zigzag() throws -> Int {
        let u = try varint()
        return Int(Int64(bitPattern: (u >> 1) ^ (0 &- (u & 1))))
    }

    mutating func u64() throws -> UInt64 {
        guard at + 8 <= bytes.count else { throw Truncated() }
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(bytes[at + k]) << (8 * k) }
        at += 8
        return v
    }

    mutating func f64() throws -> Double { Double(bitPattern: try u64()) }

    mutating func data() throws -> [UInt8] {
        let n = try count()
        guard at + n <= bytes.count else { throw Truncated() }
        defer { at += n }
        return Array(bytes[at..<(at + n)])
    }
}

/// Bytes kept whole or as a digest, as a tape stores them.
enum StoredBytes: Equatable {
    case whole([UInt8])
    case digest(UInt64)

    init(_ bytes: [UInt8], limit: Int) {
        self = bytes.count <= limit ? .whole(bytes) : .digest(Digest.of(bytes))
    }

    /// Whether `bytes` are the stored ones.
    func matches(_ bytes: [UInt8]) -> Bool {
        switch self {
        case .whole(let b): return b == bytes
        case .digest(let d): return Digest.of(bytes) == d
        }
    }

    var whole: [UInt8]? {
        if case .whole(let b) = self { return b }
        return nil
    }

    func write(_ s: inout ByteSink) {
        switch self {
        case .whole(let b): s.u8(Tape.Tag.bytes.rawValue); s.data(b)
        case .digest(let d): s.u8(Tape.Tag.digest.rawValue); s.u64(d)
        }
    }

    static func read(_ s: inout ByteSource) throws -> StoredBytes {
        switch try s.u8() {
        case Tape.Tag.bytes.rawValue: return .whole(try s.data())
        case Tape.Tag.digest.rawValue: return .digest(try s.u64())
        case let t: throw TapeError("stored bytes: tag \(t)")
        }
    }
}

struct TapeError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}

/// The answers of one test being written (the stored oracle's live mode).
final class TapeWriter {
    let url: URL
    /// The largest payload kept whole.
    let limit: Int
    private var sink = ByteSink()
    private var strings: [String: Int] = [:]
    private(set) var entries = 0
    var alignment = Digest()

    init(url: URL, limit: Int) {
        self.url = url
        self.limit = limit
        sink.bytes = Tape.magic
    }

    func tag(_ t: Tape.Tag) {
        sink.u8(t.rawValue)
        entries += 1
    }

    func bool(_ v: Bool?) { tag(v.map { $0 ? .trueValue : .falseValue } ?? .none) }

    func double(_ v: Double?) {
        guard let v else { return tag(.none) }
        tag(.double)
        sink.f64(v)
    }

    func int(_ v: Int?) {
        guard let v else { return tag(.none) }
        tag(.int)
        sink.zigzag(v)
    }

    /// A list of doubles, by their bits: whole up to the limit, else a digest.
    func doubles(_ v: [Double]?) {
        guard let v else { return tag(.none) }
        tag(.doubles)
        StoredBytes(TapeReader.encode(v), limit: limit).write(&sink)
    }

    func ints(_ v: [Int]?, whole: Bool = false) {
        guard let v else { return tag(.none) }
        var b = ByteSink()
        b.varint(v.count)
        for i in v { b.zigzag(i) }
        tag(.ints)
        StoredBytes(b.bytes, limit: whole ? .max : limit).write(&sink)
    }

    func string(_ s: String?) {
        guard let s else { return tag(.none) }
        entries += 1
        rawString(s)
    }

    /// A text with no entry of its own (inside another entry).
    func rawString(_ s: String) {
        if let i = strings[s] {
            sink.u8(Tape.Tag.stringRef.rawValue)
            sink.varint(i)
        } else {
            strings[s] = strings.count
            sink.u8(Tape.Tag.stringNew.rawValue)
            sink.data(Array(s.utf8))
        }
    }

    /// A text kept whole up to the limit, else as its digest.
    func text(_ s: String?) {
        guard let s else { return tag(.none) }
        let b = Array(s.utf8)
        if b.count <= limit { return string(s) }
        tag(.digest)
        sink.u64(Digest.of(b))
    }

    func failure(_ message: String?) {
        tag(.failure)
        if let message { rawString(message) } else { sink.u8(Tape.Tag.none.rawValue) }
    }

    /// The payload of a compound entry, after its tag.
    func raw(_ f: (inout ByteSink) -> Void) { f(&sink) }

    /// Writes the tape, compressed.
    func close() throws {
        sink.u8(Tape.Tag.end.rawValue)
        sink.varint(entries)
        sink.u64(alignment.final)
        let compressed = try (Data(sink.bytes) as NSData).compressed(using: .lzma) as Data
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try compressed.write(to: url)
    }
}

/// The answers of one test being read back (the stored oracle's frozen mode).
final class TapeReader {
    let url: URL
    private var source: ByteSource
    private var strings: [String] = []
    private(set) var entries = 0
    var alignment = Digest()

    init(url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](try (data as NSData).decompressed(using: .lzma) as Data)
        guard bytes.starts(with: Tape.magic) else { throw TapeError("\(url.lastPathComponent): not a tape") }
        source = ByteSource(bytes)
        source.at = Tape.magic.count
    }

    func tag() throws -> Tape.Tag {
        let b = try source.u8()
        guard let t = Tape.Tag(rawValue: b) else { throw TapeError("tag \(b) at \(source.at - 1)") }
        if t != .end { entries += 1 }
        return t
    }

    func bool() throws -> Bool? {
        switch try tag() {
        case .none: return nil
        case .falseValue: return false
        case .trueValue: return true
        case let t: throw TapeError("expected a boolean, found \(t)")
        }
    }

    func double() throws -> Double? {
        switch try tag() {
        case .none: return nil
        case .double: return try source.f64()
        case let t: throw TapeError("expected a number, found \(t)")
        }
    }

    func int() throws -> Int? {
        switch try tag() {
        case .none: return nil
        case .int: return try source.zigzag()
        case let t: throw TapeError("expected an integer, found \(t)")
        }
    }

    /// A list of doubles as stored: whole, or the digest of its bits.
    func doubles() throws -> StoredBytes? {
        switch try tag() {
        case .none: return nil
        case .doubles: return try StoredBytes.read(&source)
        case let t: throw TapeError("expected doubles, found \(t)")
        }
    }

    static func encode(_ v: [Double]) -> [UInt8] {
        var b = ByteSink()
        b.varint(v.count)
        for d in v { b.f64(d) }
        return b.bytes
    }

    static func decode(doubles b: [UInt8]) -> [Double] {
        var s = ByteSource(b)
        return (try? (0..<s.count()).map { _ in try s.f64() }) ?? []
    }

    /// A list of integers, as stored: whole, or the digest of its encoding.
    func ints() throws -> StoredBytes? {
        switch try tag() {
        case .none: return nil
        case .ints: return try StoredBytes.read(&source)
        case let t: throw TapeError("expected integers, found \(t)")
        }
    }

    static func encode(_ v: [Int]) -> [UInt8] {
        var b = ByteSink()
        b.varint(v.count)
        for i in v { b.zigzag(i) }
        return b.bytes
    }

    static func decode(_ b: [UInt8]) -> [Int] {
        var s = ByteSource(b)
        return (try? (0..<s.count()).map { _ in try s.zigzag() }) ?? []
    }

    func string() throws -> String? {
        switch try tag() {
        case .none: return nil
        case .stringRef, .stringNew:
            source.at -= 1
            return try rawString()
        case let t: throw TapeError("expected a text, found \(t)")
        }
    }

    func rawString() throws -> String {
        let t = try source.u8()
        guard let tag = Tape.Tag(rawValue: t) else { throw TapeError("expected a text, found tag \(t)") }
        return try rawString(after: tag)
    }

    /// A text whose tag was read already.
    func rawString(after tag: Tape.Tag) throws -> String {
        switch tag.rawValue {
        case Tape.Tag.stringRef.rawValue:
            let i = try source.count()
            guard i < strings.count else { throw TapeError("text \(i) not on the tape") }
            return strings[i]
        case Tape.Tag.stringNew.rawValue:
            let s = String(decoding: try source.data(), as: UTF8.self)
            strings.append(s)
            return s
        case let t: throw TapeError("expected a text, found tag \(t)")
        }
    }

    /// A text kept whole or as its digest.
    func text() throws -> StoredBytes? {
        switch try tag() {
        case .none: return nil
        case .stringRef, .stringNew:
            source.at -= 1
            return .whole(Array(try rawString().utf8))
        case .digest: return .digest(try source.u64())
        case let t: throw TapeError("expected a text, found \(t)")
        }
    }

    /// Reads the optional message of a failure, after its tag.
    func failureMessage() throws -> String? {
        if source.bytes[source.at] == Tape.Tag.none.rawValue {
            source.at += 1
            return nil
        }
        return try rawString()
    }

    /// The payload of a compound entry, after its tag.
    func raw<T>(_ f: (inout ByteSource) throws -> T) rethrows -> T { try f(&source) }

    /// Checks the end: every entry read and the same questions asked.
    func close() throws {
        guard try tag() == .end else { throw TapeError("entries left on the tape after \(entries)") }
        let count = try source.count(), digest = try source.u64()
        guard count == entries else { throw TapeError("\(count) entries stored, \(entries) read") }
        guard digest == alignment.final else { throw TapeError("the questions asked are not the ones stored (alignment digest)") }
    }
}

extension Optional where Wrapped == StoredBytes {
    /// Both absent, or the bytes are the stored ones.
    func matches(_ bytes: [UInt8]?) -> Bool {
        switch (self, bytes) {
        case (nil, nil): return true
        case (let s?, let b?): return s.matches(b)
        default: return false
        }
    }
}
