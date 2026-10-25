import Foundation

/// What a tile's light bake and the steps after it need, kept beside the
/// built tile as bake/scene.bin, so its light can be baked again with other
/// settings without building its geometry (Bake).
///
/// The mesh is the tile's triangles before their cut to the tile, with the
/// margin around it and the neighbours' buildings (the bake's scene, less the
/// white ground plane, which follows from `lit`), in doubles as the build
/// had them, so the cut, TEXCOORD_1 and the GLB come out byte for byte.
///
/// The file: the 8 bytes `TPSCENE1`, then LZFSE of, little-endian:
/// a UInt32 length and that much JSON (`tile` [z, x, y], `models`, the
/// landmark models' ids, `stats`, the statistics that do not depend on the
/// light), 9 Float64 (the region's bounds x0 y0 x1 y1, the light map's
/// bounds, its reach from the region's centre), a UInt32 triangle count n,
/// then n × 9 Float64 corners, n × 6 Float64 palette UVs, n × 2 Float64 wall
/// spans and n Int8 owners (Triangles).
public struct BakeScene {
    static let magic = Data("TPSCENE1".utf8)

    public var tile: [Int]
    public var models: [String]
    public var stats: [String: Any]
    public var region: (Double, Double, Double, Double)
    public var lit: (Double, Double, Double, Double)
    public var reach: Double
    public var mesh: Triangles

    public init(tile: [Int], models: [String], stats: [String: Any], region: (Double, Double, Double, Double),
                lit: (Double, Double, Double, Double), reach: Double, mesh: Triangles) {
        self.tile = tile
        self.models = models
        self.stats = stats
        self.region = region
        self.lit = lit
        self.reach = reach
        self.mesh = mesh
    }

    public func encoded() throws -> Data {
        var body = Data()
        let header = try JSONSerialization.data(withJSONObject: ["tile": tile, "models": models, "stats": stats],
                                                options: [.sortedKeys])
        func append<T>(_ values: [T]) { values.withUnsafeBytes { body.append(contentsOf: $0) } }
        append([UInt32(header.count).littleEndian])
        body.append(header)
        let bounds = [region.0, region.1, region.2, region.3, lit.0, lit.1, lit.2, lit.3, reach]
        append(bounds.map { $0.bitPattern.littleEndian })
        append([UInt32(mesh.count).littleEndian])
        append(mesh.pos.map { $0.bitPattern.littleEndian })
        append(mesh.uv.map { $0.bitPattern.littleEndian })
        append(mesh.wall.map { $0.bitPattern.littleEndian })
        append(mesh.owner.map { $0.rawValue })
        return BakeScene.magic + (try (body as NSData).compressed(using: .lzfse) as Data)
    }

    public init(_ data: Data) throws {
        guard data.prefix(BakeScene.magic.count) == BakeScene.magic else { throw PipelineError("not a bake scene") }
        let body = try (data.dropFirst(BakeScene.magic.count) as NSData).decompressed(using: .lzfse) as Data
        var at = 0
        func take(_ n: Int) throws -> Data {
            guard at + n <= body.count else { throw PipelineError("the bake scene is cut short") }
            defer { at += n }
            return body.subdata(in: at..<(at + n))
        }
        func u32() throws -> Int { Int(UInt32(littleEndian: try take(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })) }
        func doubles(_ n: Int) throws -> [Double] {
            try take(n * 8).withUnsafeBytes { raw in
                (0..<n).map { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) }
            }
        }
        let header = try JSONSerialization.jsonObject(with: try take(try u32())) as? [String: Any] ?? [:]
        tile = header["tile"] as? [Int] ?? []
        models = header["models"] as? [String] ?? []
        stats = header["stats"] as? [String: Any] ?? [:]
        let b = try doubles(9)
        region = (b[0], b[1], b[2], b[3])
        lit = (b[4], b[5], b[6], b[7])
        reach = b[8]
        let n = try u32()
        mesh = Triangles()
        mesh.pos = try doubles(n * 9)
        mesh.uv = try doubles(n * 6)
        mesh.wall = try doubles(n * 2)
        mesh.owner = try take(n).map { Owner(rawValue: Int8(bitPattern: $0)) ?? .cut }
    }
}
