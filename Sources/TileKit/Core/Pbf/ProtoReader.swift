import Foundation

/// Protocol Buffers' wire format read field by field, the little of it an
/// OSM PBF file needs: varints (plain and zigzag), length-delimited fields
/// (strings, messages, packed arrays) and the fixed widths only to skip
/// them. It reads over bytes it does not own, so it lives no longer than
/// the `withUnsafeBufferPointer` it is made in.
struct ProtoReader {
    let bytes: UnsafeBufferPointer<UInt8>
    private(set) var at: Int
    let end: Int

    /// Thrown for bytes that are no message: a varint or a field running
    /// past the end, a wire type PBF never writes.
    struct Damaged: Error {}

    init(_ bytes: UnsafeBufferPointer<UInt8>, from: Int = 0, to: Int? = nil) {
        self.bytes = bytes
        at = from
        end = to ?? bytes.count
    }

    var more: Bool { at < end }

    mutating func varint() throws -> UInt64 {
        var value: UInt64 = 0, shift: UInt64 = 0
        while true {
            guard at < end, shift < 64 else { throw Damaged() }
            let byte = bytes[at]
            at += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { return value }
            shift += 7
        }
    }

    mutating func sint() throws -> Int64 {
        let v = try varint()
        return Int64(bitPattern: (v >> 1) ^ (0 &- (v & 1)))
    }

    mutating func int() throws -> Int64 { Int64(bitPattern: try varint()) }

    /// The next field's number and wire type.
    mutating func field() throws -> (number: Int, wire: Int) {
        let key = try varint()
        return (Int(key >> 3), Int(key & 7))
    }

    /// A length-delimited field's bytes, as their range in `bytes`.
    mutating func range() throws -> Range<Int> {
        let length = Int(try varint())
        guard length >= 0, at + length <= end else { throw Damaged() }
        defer { at += length }
        return at..<(at + length)
    }

    /// A length-delimited field read as a message of its own.
    mutating func message() throws -> ProtoReader {
        let r = try range()
        return ProtoReader(bytes, from: r.lowerBound, to: r.upperBound)
    }

    mutating func skip(_ wire: Int) throws {
        switch wire {
        case 0: _ = try varint()
        case 1: at += 8
        case 2: _ = try range()
        case 5: at += 4
        default: throw Damaged()
        }
        guard at <= end else { throw Damaged() }
    }

    /// A packed field of varints, each as it comes.
    mutating func packed(_ body: (inout ProtoReader) throws -> Void) throws {
        var inner = try message()
        while inner.more { try body(&inner) }
    }

    func string(_ r: Range<Int>) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[r]), as: UTF8.self)
    }
}
