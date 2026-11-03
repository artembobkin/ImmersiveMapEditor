import Foundation

/// A cache file derived from a source file, read back only while the
/// source is the one it was made from: a header of a magic, a version and
/// the source's stamp (its size and modification time), then whatever the
/// owner wrote with `BinaryWriter`, read with `BinaryReader`. Little-endian
/// throughout, strings as a length and UTF-8. The OSM of a tile parsed from
/// Overpass's JSON (`OsmCache`) and the editor's buildings are kept this
/// way: a JSON of 24 MB with 90 thousand elements took 0.35 s to parse in
/// a release build, several times that in a debug one, every time a tile
/// was opened or built (the user, 2026-11-03: a format of our own instead
/// of JSON, for Swift).
public enum BinaryCache {
    /// A source file's size and modification time as one string: the same
    /// file fetched again gives another stamp, and the cache made from the
    /// old one is left unread.
    public static func stamp(of source: URL) -> String {
        let v = try? source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(v?.fileSize ?? 0)@\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    /// The cache at `url` opened for reading past its header, when it is
    /// there, of this magic and version, and made from a source of this
    /// stamp (any, when the source is gone and the cache stands for it:
    /// nil); nil otherwise.
    public static func read(_ url: URL, magic: String, version: UInt32, stamp: String?) -> BinaryReader? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var reader = BinaryReader(data)
        guard let m = try? reader.string(), m == magic, let v = try? reader.uint32(), v == version,
              let s = try? reader.string(), stamp == nil || s == stamp else { return nil }
        return reader
    }

    /// A writer with the header written: the owner appends its content and
    /// writes `data` to the cache's url.
    public static func writer(magic: String, version: UInt32, stamp: String) -> BinaryWriter {
        var w = BinaryWriter()
        w.string(magic)
        w.uint32(version)
        w.string(stamp)
        return w
    }
}

/// Little-endian values appended to a growing buffer.
public struct BinaryWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func uint8(_ v: UInt8) { data.append(v) }
    public mutating func uint32(_ v: UInt32) { fixed(v) }
    public mutating func int64(_ v: Int64) { fixed(v) }
    public mutating func double(_ v: Double) { fixed(v.bitPattern) }

    /// A count: as a UInt32.
    public mutating func count(_ n: Int) { uint32(UInt32(n)) }

    public mutating func string(_ s: String) {
        let bytes = Array(s.utf8)
        count(bytes.count)
        data.append(contentsOf: bytes)
    }

    private mutating func fixed<T: FixedWidthInteger>(_ v: T) {
        withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
    }
}

/// Little-endian values read in order from a buffer, each read checked
/// against its end.
public struct BinaryReader {
    public struct Short: Error {
        public init() {}
    }

    private let data: Data
    private var offset: Int

    public init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    public var atEnd: Bool { offset >= data.endIndex }

    public mutating func uint8() throws -> UInt8 {
        guard offset < data.endIndex else { throw Short() }
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func uint32() throws -> UInt32 { try fixed() }
    public mutating func int64() throws -> Int64 { try fixed() }
    public mutating func double() throws -> Double { Double(bitPattern: try fixed()) }

    /// A count, as a UInt32, checked to fit what is left (an item is a
    /// byte at least), so a corrupt file never asks for a huge array.
    public mutating func count() throws -> Int {
        let n = Int(try uint32())
        guard n <= data.endIndex - offset else { throw Short() }
        return n
    }

    public mutating func string() throws -> String {
        let n = try count()
        defer { offset += n }
        return String(decoding: data[offset..<offset + n], as: UTF8.self)
    }

    private mutating func fixed<T: FixedWidthInteger>() throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.endIndex else { throw Short() }
        defer { offset += size }
        let o = offset - data.startIndex
        return T(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: T.self) })
    }
}
