import Compression
import Foundation

/// PNG, written byte for byte as the Python build wrote it: 8-bit grey or
/// RGB, row 0 on top, one IDAT, no colour profile, so the bytes are the
/// colours the engine samples.
public enum PNG {
    public static func encode(_ pixels: [UInt8], width: Int, height: Int, channels: Int) -> Data {
        var raw = Data(capacity: (width * channels + 1) * height)
        for y in 0..<height {
            raw.append(0)
            raw.append(contentsOf: pixels[(y * width * channels)..<((y + 1) * width * channels)])
        }
        func chunk(_ tag: String, _ body: Data) -> Data {
            var d = Data()
            d.append(be(UInt32(body.count)))
            let t = Data(tag.utf8)
            d.append(t)
            d.append(body)
            d.append(be(crc32(Array(t) + Array(body))))
            return d
        }
        var header = Data()
        header.append(be(UInt32(width)))
        header.append(be(UInt32(height)))
        header.append(contentsOf: [8, channels == 1 ? 0 : 2, 0, 0, 0])
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        out.append(chunk("IHDR", header))
        out.append(chunk("IDAT", zlib(raw)))
        out.append(chunk("IEND", Data()))
        return out
    }

    public static func write(_ url: URL, _ pixels: [UInt8], width: Int, height: Int, channels: Int) throws {
        try encode(pixels, width: width, height: height, channels: channels).write(to: url)
    }

    static func be(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }

    /// A zlib stream: header, raw deflate, Adler-32.
    static func zlib(_ data: Data) -> Data {
        var out = Data([0x78, 0xDA])
        let capacity = data.count + data.count / 10 + 1024
        var buffer = [UInt8](repeating: 0, count: capacity)
        let n = data.withUnsafeBytes { src in
            compression_encode_buffer(&buffer, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                      nil, COMPRESSION_ZLIB)
        }
        out.append(contentsOf: buffer[0..<n])
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        out.append(be(b << 16 | a))
        return out
    }
}
