import Foundation
import TileKit
import MetalKit

/// A built tile (out/tiles/<z>/<x>/<y>/) on the GPU: its one mesh, its
/// palette and light map, read from its GLB as the engine's tooling reads it
/// (CLAUDE.md, "The model file: GLB"), and where it lies among the others.
struct TileModel {
    let x, y: Int
    let positions: MTLBuffer
    let uv0: MTLBuffer
    let uv1: MTLBuffer
    let indices: MTLBuffer
    let indexCount: Int
    let indexType: MTLIndexType
    let palette: MTLTexture
    let light: MTLTexture
    /// The tile's centre in the document's metres (east, north), and the
    /// scale from its own metres to the document's: the Mercator scale
    /// changes a little from row to row.
    let centre: Vec2
    let scale: Double
    let triangles: Int
    let built: Date?

    enum Failure: LocalizedError {
        case glb(String)
        var errorDescription: String? { if case .glb(let s) = self { return s }; return nil }
    }

    /// The folder of a tile's build.
    static func folder(root: URL, z: Int, x: Int, y: Int) -> URL {
        root.appendingPathComponent("out/tiles/\(z)/\(x)/\(y)")
    }

    static func load(device: MTLDevice, root: URL, z: Int, x: Int, y: Int, region: Region) throws -> TileModel {
        let folder = folder(root: root, z: z, x: x, y: y)
        let placement = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("placement.json")))
        guard let model = (placement as? [String: Any])?["model"] as? String else { throw Failure.glb("no model in placement.json") }
        let url = folder.appendingPathComponent(model)
        let data = try Data(contentsOf: url)
        let (json, bin) = try chunks(data)

        func array(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }
        let accessors = array("accessors"), views = array("bufferViews")
        guard let prim = (array("meshes").first?["primitives"] as? [[String: Any]])?.first,
              let attrs = prim["attributes"] as? [String: Int],
              let pos = attrs["POSITION"], let t0 = attrs["TEXCOORD_0"], let t1 = attrs["TEXCOORD_1"],
              let ind = prim["indices"] as? Int else { throw Failure.glb("not one indexed primitive with two UVs") }

        /// The bytes of an accessor, tightly packed.
        func bytes(_ index: Int, width: Int) throws -> (Data, Int, Int) {
            let a = accessors[index]
            guard let v = a["bufferView"] as? Int, let count = a["count"] as? Int, let kind = a["componentType"] as? Int
            else { throw Failure.glb("accessor \(index)") }
            let size = kind == 5126 || kind == 5125 ? 4 : kind == 5123 ? 2 : 1
            let view = views[v]
            let start = (view["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
            let stride = view["byteStride"] as? Int ?? size * width
            if stride == size * width {
                return (bin.subdata(in: start..<(start + count * stride)), count, kind)
            }
            var out = Data(capacity: count * size * width)
            for i in 0..<count {
                out.append(bin.subdata(in: (start + i * stride)..<(start + i * stride + size * width)))
            }
            return (out, count, kind)
        }
        func buffer(_ d: Data) -> MTLBuffer? {
            d.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(d.count, 4)) }
        }
        let (p, _, _) = try bytes(pos, width: 3)
        let (u0, _, _) = try bytes(t0, width: 2)
        let (u1, _, _) = try bytes(t1, width: 2)
        let (ix, count, kind) = try bytes(ind, width: 1)
        guard kind == 5125 || kind == 5123 else { throw Failure.glb("indices are not u16 or u32") }

        // The material: the palette its base colour, the light map its occlusion.
        guard let material = array("materials").first,
              let base = ((material["pbrMetallicRoughness"] as? [String: Any])?["baseColorTexture"] as? [String: Any])?["index"] as? Int,
              let occlusion = (material["occlusionTexture"] as? [String: Any])?["index"] as? Int
        else { throw Failure.glb("no palette and light map in the material") }
        let loader = MTKTextureLoader(device: device)
        func texture(_ textureIndex: Int) throws -> MTLTexture {
            guard let source = array("textures")[textureIndex]["source"] as? Int,
                  let v = array("images")[source]["bufferView"] as? Int else { throw Failure.glb("texture \(textureIndex)") }
            let view = views[v]
            let start = view["byteOffset"] as? Int ?? 0, length = view["byteLength"] as? Int ?? 0
            // Raw values, as the engine samples them: no sRGB decode.
            return try loader.newTexture(data: bin.subdata(in: start..<(start + length)), options: [
                .SRGB: false, .generateMipmaps: true, .textureStorageMode: MTLStorageMode.private.rawValue,
            ])
        }

        let own = Region(z: z, x0: x, y0: y, x1: x, y1: y)
        let centre = Vec2((own.gx - region.gx) / region.unitsPerMetre, (region.gy - own.gy) / region.unitsPerMetre)
        guard let pb = buffer(p), let b0 = buffer(u0), let b1 = buffer(u1), let bi = buffer(ix) else { throw Failure.glb("no GPU memory") }
        let built = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return TileModel(x: x, y: y, positions: pb, uv0: b0, uv1: b1, indices: bi, indexCount: count,
                         indexType: kind == 5125 ? .uint32 : .uint16, palette: try texture(base), light: try texture(occlusion),
                         centre: centre, scale: own.unitsPerMetre / region.unitsPerMetre, triangles: count / 3, built: built)
    }

    /// The JSON and binary chunks of a GLB.
    static func chunks(_ data: Data) throws -> ([String: Any], Data) {
        func u32(_ at: Int) -> Int { Int(data.subdata(in: at..<(at + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) }
        guard data.count > 20, u32(0) == 0x4654_6C67, u32(4) == 2 else { throw Failure.glb("not a glTF 2.0 binary") }
        var at = 12
        var json: [String: Any]?
        var bin = Data()
        while at + 8 <= data.count {
            let length = u32(at), kind = u32(at + 4)
            let body = data.subdata(in: (at + 8)..<(at + 8 + length))
            if kind == 0x4E4F_534A { json = try JSONSerialization.jsonObject(with: body) as? [String: Any] }
            if kind == 0x004E_4942 { bin = body }
            at += 8 + length
        }
        guard let json else { throw Failure.glb("no JSON chunk") }
        return (json, bin)
    }
}
