import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// Mapillary's coverage tiles (Mapbox vector tiles, zoom 14, the `image`
/// layer: every photo as a point with its id, compass angle, date, pano
/// flag and sequence): the complete and steady list of what is there,
/// where the Graph API's box search answers with a different sample every
/// time. Only what the points need of the protobuf is read.
enum CoverageTile {
    struct Point {
        let lon: Double, lat: Double
        let props: [String: Any]
    }

    static let zoom = 14

    /// The tile holding a longitude and latitude.
    static func tile(lon: Double, lat: Double) -> (x: Int, y: Int) {
        let n = Double(1 << zoom), r = lat * .pi / 180
        return (Int((lon + 180) / 360 * n), Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n))
    }

    /// The points of a tile's `image` layer, in longitude and latitude.
    static func points(_ data: Data, x: Int, y: Int) -> [Point] {
        var out: [Point] = []
        let n = Double(1 << zoom)
        var tile = Reader(Array(data))
        while let (field, wire) = tile.key() {
            guard field == 3, wire == 2, let layer = tile.bytes() else { tile.skip(wire); continue }
            var r = Reader(layer)
            var name = "", extent = 4096.0
            var keys: [String] = [], values: [Any] = [], features: [[UInt8]] = []
            while let (f, w) = r.key() {
                switch (f, w) {
                case (1, 2): name = r.string() ?? ""
                case (2, 2): if let b = r.bytes() { features.append(b) }
                case (3, 2): keys.append(r.string() ?? "")
                case (4, 2): if let b = r.bytes() { values.append(value(b)) }
                case (5, 0): extent = Double(r.varint())
                default: r.skip(w)
                }
            }
            guard name == "image" else { continue }
            for feature in features {
                var fr = Reader(feature)
                var tags: [UInt64] = [], geometry: [UInt64] = [], type = 0
                while let (f, w) = fr.key() {
                    switch (f, w) {
                    case (2, 2): tags = fr.packed()
                    case (3, 0): type = Int(fr.varint())
                    case (4, 2): geometry = fr.packed()
                    default: fr.skip(w)
                    }
                }
                guard type == 1, geometry.count >= 3, geometry[0] & 7 == 1 else { continue }
                var props: [String: Any] = [:]
                for i in stride(from: 0, to: tags.count - 1, by: 2) where Int(tags[i]) < keys.count && Int(tags[i + 1]) < values.count {
                    props[keys[Int(tags[i])]] = values[Int(tags[i + 1])]
                }
                let px = Double(zigzag(geometry[1])), py = Double(zigzag(geometry[2]))
                let lon = (Double(x) + px / extent) / n * 360 - 180
                let lat = atan(sinh(.pi * (1 - 2 * (Double(y) + py / extent) / n))) * 180 / .pi
                out.append(Point(lon: lon, lat: lat, props: props))
            }
        }
        return out
    }

    static func zigzag(_ v: UInt64) -> Int64 { Int64(v >> 1) ^ -Int64(v & 1) }

    static func value(_ bytes: [UInt8]) -> Any {
        var r = Reader(bytes)
        while let (f, w) = r.key() {
            switch (f, w) {
            case (1, 2): return r.string() ?? ""
            case (2, 5): return Double(Float(bitPattern: UInt32(r.fixed(4))))
            case (3, 1): return Double(bitPattern: r.fixed(8))
            case (4, 0): return Int64(bitPattern: r.varint())
            case (5, 0): return r.varint()
            case (6, 0): return zigzag(r.varint())
            case (7, 0): return r.varint() != 0
            default: r.skip(w)
            }
        }
        return ""
    }

    /// A protobuf reader of the little a tile needs.
    struct Reader {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        mutating func varint() -> UInt64 {
            var v: UInt64 = 0, shift: UInt64 = 0
            while i < b.count {
                let byte = b[i]
                i += 1
                v |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            return v
        }

        mutating func key() -> (Int, Int)? {
            guard i < b.count else { return nil }
            let k = varint()
            return (Int(k >> 3), Int(k & 7))
        }

        mutating func bytes() -> [UInt8]? {
            let n = Int(varint())
            guard i + n <= b.count else { i = b.count; return nil }
            defer { i += n }
            return Array(b[i..<(i + n)])
        }

        mutating func string() -> String? { bytes().flatMap { String(bytes: $0, encoding: .utf8) } }

        mutating func packed() -> [UInt64] {
            guard let inner = bytes() else { return [] }
            var r = Reader(inner), out: [UInt64] = []
            while r.i < inner.count { out.append(r.varint()) }
            return out
        }

        mutating func fixed(_ n: Int) -> UInt64 {
            var v: UInt64 = 0
            for k in 0..<n where i + k < b.count { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
            i += n
            return v
        }

        mutating func skip(_ wire: Int) {
            switch wire {
            case 0: _ = varint()
            case 1: i += 8
            case 2: _ = bytes()
            case 5: i += 4
            default: i = b.count
            }
        }
    }
}
