import Compression
import Foundation

/// An OSM PBF file (`.osm.pbf`, what Geofabrik and planet.openstreetmap.org
/// give), read blob by blob from the file mapped into memory: each blob a
/// 4-byte big-endian length, a `BlobHeader` (its type, "OSMHeader" or
/// "OSMData", and its size) and a `Blob`, raw or zlib-compressed. The
/// format: wiki.openstreetmap.org/wiki/PBF_Format.
struct PbfFile {
    let url: URL
    let data: Data

    /// A blob's place in the file: where its `Blob` message starts, its
    /// size and its type.
    struct BlobPlace {
        var offset: Int
        var size: Int
        var isData: Bool
    }

    /// What the file's `HeaderBlock` says: the box its data covers, in
    /// degrees, and the replication timestamp of the data, when given.
    struct Header {
        var south, west, north, east: Double
        var hasBox: Bool
        var timestamp: Date?
    }

    init(_ url: URL) throws {
        self.url = url
        data = try Data(contentsOf: url, options: .alwaysMapped)
    }

    /// Every blob of the file, in order, its headers read, no blob decoded;
    /// only the first with `first`.
    func places(first: Bool = false) throws -> [BlobPlace] {
        try data.withUnsafeBytes { raw -> [BlobPlace] in
            let bytes = raw.bindMemory(to: UInt8.self)
            var out: [BlobPlace] = []
            var at = 0
            while at < bytes.count {
                guard at + 4 <= bytes.count else { throw damaged("a blob's length is cut off") }
                let length = Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
                at += 4
                guard length > 0, at + length <= bytes.count else { throw damaged("a blob header runs past the end") }
                var header = ProtoReader(bytes, from: at, to: at + length)
                var type = "", size = 0
                while header.more {
                    let f = try header.field()
                    switch f.number {
                    case 1: type = header.string(try header.range())
                    case 3: size = Int(try header.varint())
                    default: try header.skip(f.wire)
                    }
                }
                at += length
                guard size > 0, at + size <= bytes.count else { throw damaged("a blob runs past the end") }
                out.append(BlobPlace(offset: at, size: size, isData: type == "OSMData"))
                at += size
                if first { break }
            }
            return out
        }
    }

    /// The file's header block: the first blob, which is always it.
    func header() throws -> Header {
        guard let first = try places(first: true).first, !first.isData else { throw damaged("it starts with no OSMHeader") }
        let block = try blob(first)
        return try block.withUnsafeBufferPointer { bytes in
            var r = ProtoReader(bytes)
            var header = Header(south: -90, west: -180, north: 90, east: 180, hasBox: false, timestamp: nil)
            while r.more {
                let f = try r.field()
                switch f.number {
                case 1:
                    var box = try r.message()
                    var left: Int64 = 0, right: Int64 = 0, top: Int64 = 0, bottom: Int64 = 0
                    while box.more {
                        let g = try box.field()
                        switch g.number {
                        case 1: left = try box.sint()
                        case 2: right = try box.sint()
                        case 3: top = try box.sint()
                        case 4: bottom = try box.sint()
                        default: try box.skip(g.wire)
                        }
                    }
                    header.west = Double(left) * 1e-9
                    header.east = Double(right) * 1e-9
                    header.north = Double(top) * 1e-9
                    header.south = Double(bottom) * 1e-9
                    header.hasBox = true
                case 4:
                    let feature = r.string(try r.range())
                    guard ["OsmSchema-V0.6", "DenseNodes"].contains(feature) else {
                        throw PipelineError("\(url.lastPathComponent) needs \"\(feature)\", which this reader does not know")
                    }
                case 32:
                    header.timestamp = Date(timeIntervalSince1970: TimeInterval(try r.int()))
                default:
                    try r.skip(f.wire)
                }
            }
            return header
        }
    }

    /// A blob's content, decompressed.
    func blob(_ place: BlobPlace) throws -> [UInt8] {
        try data.withUnsafeBytes { raw -> [UInt8] in
            let bytes = raw.bindMemory(to: UInt8.self)
            var r = ProtoReader(bytes, from: place.offset, to: place.offset + place.size)
            var rawSize = 0
            var plain: Range<Int>?, zlib: Range<Int>?
            while r.more {
                let f = try r.field()
                switch f.number {
                case 1: plain = try r.range()
                case 2: rawSize = Int(try r.varint())
                case 3: zlib = try r.range()
                case 4, 6, 7: throw PipelineError("\(url.lastPathComponent) is compressed with other than zlib, which this reader does not know")
                default: try r.skip(f.wire)
                }
            }
            if let plain { return Array(bytes[plain]) }
            // zlib's stream: two bytes of header, the deflate data, four of
            // checksum. Apple's ZLIB decoder reads the raw deflate data.
            guard let zlib, zlib.count > 6, rawSize > 0 else { throw damaged("a blob with no data") }
            var out = [UInt8](repeating: 0, count: rawSize)
            let written = out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, rawSize, bytes.baseAddress! + zlib.lowerBound + 2, zlib.count - 2,
                                          nil, COMPRESSION_ZLIB)
            }
            guard written == rawSize else { throw damaged("a blob does not decompress to its size") }
            return out
        }
    }

    private func damaged(_ what: String) -> PipelineError {
        PipelineError("\(url.lastPathComponent) is no OSM PBF file or is damaged: \(what)")
    }
}
