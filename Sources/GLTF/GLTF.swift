import CoreGraphics
import Foundation
import ImageIO
import simd

/// glTF 2.0 binaries read and written: Foundation for the geometry, ImageIO
/// for the images.
///
/// - `read`: the triangles of every mesh in the default scene, with each
///   node's transform applied, turned from glTF's +Y up into the build's +Z
///   up ((x, y, z) to (x, -z, y), as Blender's importer turned them), and
///   with UVs and images with V up (image rows from the bottom), so the code
///   written against Blender's importer reads them alike.
/// - `primitives` and `writeModel`: a model's parts with their materials and
///   textures as they came, for fitting a downloaded landmark.
/// - `write`: one indexed mesh, one material with two embedded PNG
///   textures, the layout of a tile (TilePipeline's CLAUDE.md, "The model
///   file: GLB").
public enum GLTF {
    public enum Failure: LocalizedError {
        case format(String)
        public var errorDescription: String? { if case .format(let s) = self { return s }; return nil }
    }

    /// One triangle of a model: its corners (+Z up), its UVs (V up) or nil,
    /// the key of its image (never empty) or nil, its material's base colour
    /// (0...255 sRGB).
    public struct Triangle {
        public var corners: [SIMD3<Double>]
        public var uvs: [SIMD2<Double>]?
        public var image: String?
        public var base: (Int, Int, Int)
        /// The material's name, when it has one.
        public var material: String?
    }

    /// An image as RGBA floats 0...1, rows from the bottom.
    public struct Image {
        public let width, height: Int
        public let rgba: [Float]

        /// The RGB at a row (from the bottom) and a column.
        public func rgb(_ row: Int, _ col: Int) -> SIMD3<Float> {
            let k = (row * width + col) * 4
            return SIMD3(rgba[k], rgba[k + 1], rgba[k + 2])
        }
    }

    /// A material as it came: its name, its linear base colour factor, its
    /// texture's encoded bytes and type.
    public struct Material {
        public var name: String
        public var factor: [Double]
        public var image: Data?
        public var mime: String?

        public init(name: String, factor: [Double], image: Data? = nil, mime: String? = nil) {
            self.name = name
            self.factor = factor
            self.image = image
            self.mime = mime
        }
    }

    /// A primitive as it came: its triangles (+Z up), three corners each,
    /// and their UVs in glTF's own convention (V down), or nil.
    public struct Part {
        public var material: Material
        public var tris: [SIMD3<Double>]
        public var uvs: [SIMD2<Double>]?

        public init(material: Material, tris: [SIMD3<Double>], uvs: [SIMD2<Double>]?) {
            self.material = material
            self.tris = tris
            self.uvs = uvs
        }
    }

    // MARK: Reading

    struct Document {
        let json: [String: Any]
        let buffers: [Data]
        let url: URL

        func array(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }
    }

    /// The JSON and the binary buffers of a .glb or a .gltf.
    static func load(_ url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        func u32(_ at: Int) -> Int {
            Int(data.subdata(in: at..<(at + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        }
        if data.count >= 12, data.prefix(4) == Data("glTF".utf8) {
            var at = 12
            var json: [String: Any]?
            var chunks: [Data] = []
            while at + 8 <= data.count {
                let size = u32(at), kind = u32(at + 4)
                let body = data.subdata(in: (at + 8)..<min(data.count, at + 8 + size))
                if kind == 0x4E4F_534A {
                    json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                } else {
                    chunks.append(body)
                }
                at += 8 + size
            }
            guard let json else { throw Failure.format("\(url.lastPathComponent): no JSON chunk") }
            let buffers = try (json["buffers"] as? [[String: Any]] ?? []).map { b -> Data in
                if let uri = b["uri"] as? String { return try resource(url, uri) }
                return chunks.first ?? Data()
            }
            return Document(json: json, buffers: buffers, url: url)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.format("\(url.lastPathComponent): not glTF")
        }
        let buffers = try (json["buffers"] as? [[String: Any]] ?? []).map { try resource(url, $0["uri"] as? String ?? "") }
        return Document(json: json, buffers: buffers, url: url)
    }

    static func resource(_ url: URL, _ uri: String) throws -> Data {
        if uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") {
            return Data(base64Encoded: String(uri[uri.index(after: comma)...])) ?? Data()
        }
        return try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(uri))
    }

    static let widths = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16]

    /// An accessor's values, `width` per element, normalised integers
    /// scaled to 0...1.
    static func accessor(_ doc: Document, _ index: Int) -> (values: [Double], width: Int) {
        let a = doc.array("accessors")[index]
        let width = widths[a["type"] as? String ?? "SCALAR"] ?? 1
        let count = a["count"] as? Int ?? 0
        guard let v = a["bufferView"] as? Int else { return ([Double](repeating: 0, count: count * width), width) }
        let kind = a["componentType"] as? Int ?? 5126
        let size = [5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4][kind] ?? 4
        let view = doc.array("bufferViews")[v]
        let raw = doc.buffers[view["buffer"] as? Int ?? 0]
        let start = (view["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
        let stride = (view["byteStride"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? size * width
        let normalized = a["normalized"] as? Bool ?? false
        var out = [Double](repeating: 0, count: count * width)
        raw.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            for i in 0..<count {
                for k in 0..<width {
                    let at = start + i * stride + k * size
                    let value: Double
                    switch kind {
                    case 5120: value = Double(p.loadUnaligned(fromByteOffset: at, as: Int8.self)) / (normalized ? 127 : 1)
                    case 5121: value = Double(p.loadUnaligned(fromByteOffset: at, as: UInt8.self)) / (normalized ? 255 : 1)
                    case 5122: value = Double(p.loadUnaligned(fromByteOffset: at, as: Int16.self)) / (normalized ? 32767 : 1)
                    case 5123: value = Double(p.loadUnaligned(fromByteOffset: at, as: UInt16.self)) / (normalized ? 65535 : 1)
                    case 5125: value = Double(p.loadUnaligned(fromByteOffset: at, as: UInt32.self)) / (normalized ? 4294967295 : 1)
                    default: value = Double(p.loadUnaligned(fromByteOffset: at, as: Float.self))
                    }
                    out[i * width + k] = value
                }
            }
        }
        return (out, width)
    }

    static func local(_ node: [String: Any]) -> simd_double4x4 {
        if let m = node["matrix"] as? [Double], m.count == 16 {
            return simd_double4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
                                            SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
        }
        let t = node["translation"] as? [Double] ?? [0, 0, 0]
        let r = node["rotation"] as? [Double] ?? [0, 0, 0, 1]
        let s = node["scale"] as? [Double] ?? [1, 1, 1]
        let (x, y, z, w) = (r[0], r[1], r[2], r[3])
        let rows = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                    [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                    [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        var m = matrix_identity_double4x4
        for i in 0..<3 {
            for j in 0..<3 { m[j][i] = rows[i][j] * s[j] }
            m[3][i] = t[i]
        }
        return m
    }

    /// Every mesh primitive of the default scene with its world transform:
    /// (transform, primitive).
    static func visit(_ doc: Document, _ body: (simd_double4x4, [String: Any]) -> Void) {
        let nodes = doc.array("nodes")
        func walk(_ n: Int, _ parent: simd_double4x4) {
            let node = nodes[n]
            let m = parent * local(node)
            if let mesh = node["mesh"] as? Int {
                for prim in doc.array("meshes")[mesh]["primitives"] as? [[String: Any]] ?? []
                where (prim["mode"] as? Int ?? 4) == 4 {
                    body(m, prim)
                }
            }
            for c in node["children"] as? [Int] ?? [] { walk(c, m) }
        }
        let scenes = doc.array("scenes")
        let roots = scenes.isEmpty ? Array(nodes.indices)
            : scenes[doc.json["scene"] as? Int ?? 0]["nodes"] as? [Int] ?? []
        for n in roots { walk(n, matrix_identity_double4x4) }
    }

    /// The corners of a primitive in +Z up, three per triangle, wound back
    /// if its transform mirrors, with the matching corner indices.
    static func corners(_ doc: Document, _ m: simd_double4x4, _ prim: [String: Any]) -> ([SIMD3<Double>], [Int]) {
        let attrs = prim["attributes"] as? [String: Int] ?? [:]
        guard let pa = attrs["POSITION"] else { return ([], []) }
        let (p, _) = accessor(doc, pa)
        let pos = (0..<(p.count / 3)).map { i -> SIMD3<Double> in
            let w = m * SIMD4(p[3 * i], p[3 * i + 1], p[3 * i + 2], 1)
            return SIMD3(w.x, -w.z, w.y)
        }
        var idx = (prim["indices"] as? Int).map { accessor(doc, $0).values.map { Int($0) } } ?? Array(pos.indices)
        idx = Array(idx.prefix(idx.count / 3 * 3))
        let r = simd_double3x3(SIMD3(m[0].x, m[0].y, m[0].z), SIMD3(m[1].x, m[1].y, m[1].z), SIMD3(m[2].x, m[2].y, m[2].z))
        if r.determinant < 0 {
            for t in stride(from: 0, to: idx.count, by: 3) { idx.swapAt(t, t + 2) }
        }
        return (pos, idx)
    }

    /// Every triangle of the default scene, and the images by key.
    public static func read(_ url: URL) throws -> ([Triangle], [String: Image]) {
        let doc = try load(url)
        var images: [String: Image] = [:]

        func image(_ index: Int) -> String? {
            let key = "image\(index)"
            if images[key] != nil { return key }
            guard let data = imageData(doc, index), let img = decode(data) else { return nil }
            images[key] = img
            return key
        }

        func material(_ index: Int?) -> (String?, (Int, Int, Int), String?) {
            guard let index else { return (nil, (200, 200, 200), nil) }
            let name = doc.array("materials")[index]["name"] as? String
            let pbr = doc.array("materials")[index]["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            let lin = (pbr["baseColorFactor"] as? [Double] ?? [1, 1, 1, 1]).prefix(3).map { $0 }
            func srgb(_ c: Double) -> Int {
                Int((255 * (c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055)).rounded(.toNearestOrEven))
            }
            let base = (srgb(lin[0]), srgb(lin[1]), srgb(lin[2]))
            guard let tex = pbr["baseColorTexture"] as? [String: Any], let t = tex["index"] as? Int,
                  let source = doc.array("textures")[t]["source"] as? Int else { return (nil, base, name) }
            return (image(source), base, name)
        }

        var out: [Triangle] = []
        visit(doc) { m, prim in
            let (pos, idx) = corners(doc, m, prim)
            let attrs = prim["attributes"] as? [String: Int] ?? [:]
            let uv: [SIMD2<Double>]? = attrs["TEXCOORD_0"].map { a in
                let v = accessor(doc, a).values
                return (0..<(v.count / 2)).map { SIMD2(v[2 * $0], 1 - v[2 * $0 + 1]) }
            }
            let (img, base, name) = material(prim["material"] as? Int)
            for t in stride(from: 0, to: idx.count, by: 3) {
                let tri = [idx[t], idx[t + 1], idx[t + 2]]
                out.append(Triangle(corners: tri.map { pos[$0] }, uvs: uv.map { u in tri.map { u[$0] } },
                                    image: uv != nil ? img : nil, base: base, material: name))
            }
        }
        return (out, images)
    }

    static func imageData(_ doc: Document, _ index: Int) -> Data? {
        let img = doc.array("images")[index]
        if let v = img["bufferView"] as? Int {
            let view = doc.array("bufferViews")[v]
            let start = view["byteOffset"] as? Int ?? 0, length = view["byteLength"] as? Int ?? 0
            return doc.buffers[view["buffer"] as? Int ?? 0].subdata(in: start..<(start + length))
        }
        return (img["uri"] as? String).flatMap { try? resource(doc.url, $0) }
    }

    /// An encoded image as RGBA floats, rows from the bottom: the decoded
    /// bytes as they are, with no colour management (as Pillow gives them).
    public static func decode(_ data: Data) -> Image? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let model = cg.colorSpace?.model
        let alpha = cg.alphaInfo
        let order = cg.bitmapInfo.intersection(.byteOrderMask)
        let plain = order == [] || order == .byteOrder32Big || order == .byteOrderDefault
        if cg.bitsPerComponent == 8, plain, model == .rgb || model == .monochrome,
           let bytes = cg.dataProvider?.data as Data? {
            let comps = cg.bitsPerPixel / 8
            let first = alpha == .first || alpha == .premultipliedFirst || alpha == .noneSkipFirst
            let hasAlpha = alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast
            bytes.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                for y in 0..<h {
                    for x in 0..<w {
                        let s = y * cg.bytesPerRow + x * comps, d = (y * w + x) * 4
                        if model == .monochrome {
                            rgba[d] = p[s]; rgba[d + 1] = p[s]; rgba[d + 2] = p[s]
                            rgba[d + 3] = comps > 1 && hasAlpha ? p[s + 1] : 255
                        } else {
                            let c = first ? s + 1 : s
                            rgba[d] = p[c]; rgba[d + 1] = p[c + 1]; rgba[d + 2] = p[c + 2]
                            rgba[d + 3] = hasAlpha ? p[first ? s : s + 3] : 255
                        }
                    }
                }
            }
        } else {
            // Anything else drawn into plain RGBA in the image's own space.
            let space = model == .rgb ? cg.colorSpace! : CGColorSpaceCreateDeviceRGB()
            guard let c = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            // Its memory holds the top row first, as the decoded bytes do.
            c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // Rows from the bottom.
        var out = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let src = (h - 1 - y) * w * 4, dst = y * w * 4
            for k in 0..<(w * 4) { out[dst + k] = Float(rgba[src + k]) / 255 }
        }
        return Image(width: w, height: h, rgba: out)
    }

    /// Every primitive of the default scene as it came, with its node's
    /// transform applied, in +Z up.
    public static func primitives(_ url: URL) throws -> [Part] {
        let doc = try load(url)
        func material(_ index: Int?) -> Material {
            guard let index else { return Material(name: "", factor: [1, 1, 1, 1]) }
            let mat = doc.array("materials")[index]
            let pbr = mat["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            var out = Material(name: mat["name"] as? String ?? "", factor: pbr["baseColorFactor"] as? [Double] ?? [1, 1, 1, 1])
            if let tex = pbr["baseColorTexture"] as? [String: Any], let t = tex["index"] as? Int,
               let source = doc.array("textures")[t]["source"] as? Int, let data = imageData(doc, source) {
                out.image = data
                out.mime = doc.array("images")[source]["mimeType"] as? String
                    ?? (data.prefix(2) == Data([0xFF, 0xD8]) ? "image/jpeg" : "image/png")
            }
            return out
        }
        var out: [Part] = []
        visit(doc) { m, prim in
            let (pos, idx) = corners(doc, m, prim)
            let attrs = prim["attributes"] as? [String: Int] ?? [:]
            let uv: [SIMD2<Double>]? = attrs["TEXCOORD_0"].map { a in
                let v = accessor(doc, a).values
                return (0..<(v.count / 2)).map { SIMD2(v[2 * $0], v[2 * $0 + 1]) }
            }
            out.append(Part(material: material(prim["material"] as? Int), tris: idx.map { pos[$0] },
                            uvs: uv.map { u in idx.map { u[$0] } }))
        }
        return out
    }

    // MARK: Writing

    /// JSON with its keys in the order given.
    indirect enum JSON {
        case object([(String, JSON)])
        case array([JSON])
        case int(Int)
        case number(Double)
        case string(String)

        var text: String {
            switch self {
            case .object(let pairs): return "{" + pairs.map { "\(JSON.string($0.0).text):\($0.1.text)" }.joined(separator: ",") + "}"
            case .array(let items): return "[" + items.map(\.text).joined(separator: ",") + "]"
            case .int(let i): return String(i)
            case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? String(format: "%.1f", d) : "\(d)"
            case .string(let s):
                let data = try! JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
                return String(data: data, encoding: .utf8)!
            }
        }
    }

    /// The binary chunk being laid out: buffer views and accessors.
    final class Blob {
        var data = Data()
        var views: [JSON] = []
        var accessors: [JSON] = []

        func add(_ bytes: Data, target: Int? = nil) -> Int {
            var view: [(String, JSON)] = [("buffer", .int(0)), ("byteOffset", .int(data.count)), ("byteLength", .int(bytes.count))]
            if let target { view.append(("target", .int(target))) }
            data.append(bytes)
            data.append(Data(repeating: 0, count: (4 - bytes.count % 4) % 4))
            views.append(.object(view))
            return views.count - 1
        }

        func attribute(_ values: [Float], width: Int, bounds: Bool = false) -> Int {
            let count = values.count / width
            let bytes = values.withUnsafeBufferPointer { Data(buffer: $0) }
            var acc: [(String, JSON)] = [("bufferView", .int(add(bytes, target: 34962))), ("componentType", .int(5126)),
                                         ("count", .int(count)), ("type", .string(width == 2 ? "VEC2" : "VEC3"))]
            if bounds {
                var lo = [Float](repeating: .infinity, count: width), hi = [Float](repeating: -.infinity, count: width)
                for i in 0..<count {
                    for k in 0..<width {
                        lo[k] = min(lo[k], values[i * width + k])
                        hi[k] = max(hi[k], values[i * width + k])
                    }
                }
                acc.append(("min", .array(lo.map { .number(Double($0)) })))
                acc.append(("max", .array(hi.map { .number(Double($0)) })))
            }
            accessors.append(.object(acc))
            return accessors.count - 1
        }

        func indices(_ idx: [UInt32]) -> Int {
            let bytes = idx.withUnsafeBufferPointer { Data(buffer: $0) }
            accessors.append(.object([("bufferView", .int(add(bytes, target: 34963))), ("componentType", .int(5125)),
                                      ("count", .int(idx.count)), ("type", .string("SCALAR"))]))
            return accessors.count - 1
        }
    }

    static func glb(_ url: URL, _ doc: [(String, JSON)], _ blob: Blob) throws {
        var body = Data(JSON.object(doc).text.utf8)
        body.append(Data(repeating: 0x20, count: (4 - body.count % 4) % 4))
        func u32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        var out = Data("glTF".utf8)
        out.append(u32(2))
        out.append(u32(12 + 8 + body.count + 8 + blob.data.count))
        out.append(u32(body.count)); out.append(Data("JSON".utf8)); out.append(body)
        out.append(u32(blob.data.count)); out.append(Data("BIN\0".utf8)); out.append(blob.data)
        try out.write(to: url)
    }

    /// A model of several materials: each part a primitive of its own,
    /// written +Y up with flat normals.
    public static func writeModel(_ url: URL, _ parts: [Part], name: String = "model") throws {
        let blob = Blob()
        var materials: [JSON] = [], images: [JSON] = [], textures: [JSON] = [], prims: [JSON] = []
        for part in parts where !part.tris.isEmpty {
            var pos: [Float] = [], nor: [Float] = []
            for t in stride(from: 0, to: part.tris.count, by: 3) {
                let a = part.tris[t], b = part.tris[t + 1], c = part.tris[t + 2]
                var n = simd_cross(b - a, c - a)
                n /= max(simd_length(n), 1e-12)
                for p in [a, b, c] {
                    pos += [Float(p.x), Float(p.z), Float(-p.y)]
                    nor += [Float(n.x), Float(n.z), Float(-n.y)]
                }
            }
            var attrs: [(String, JSON)] = [("POSITION", .int(blob.attribute(pos, width: 3, bounds: true))),
                                           ("NORMAL", .int(blob.attribute(nor, width: 3)))]
            if let uvs = part.uvs {
                attrs.append(("TEXCOORD_0", .int(blob.attribute(uvs.flatMap { [Float($0.x), Float($0.y)] }, width: 2))))
            }
            let mat = part.material
            var pbr: [(String, JSON)] = [("baseColorFactor", .array(mat.factor.map { .number($0) })),
                                         ("metallicFactor", .number(0)), ("roughnessFactor", .number(1))]
            if let image = mat.image, part.uvs != nil {
                images.append(.object([("bufferView", .int(blob.add(image))), ("mimeType", .string(mat.mime ?? "image/png"))]))
                textures.append(.object([("sampler", .int(0)), ("source", .int(images.count - 1))]))
                pbr.append(("baseColorTexture", .object([("index", .int(textures.count - 1))])))
            }
            materials.append(.object([("name", .string(mat.name)), ("pbrMetallicRoughness", .object(pbr))]))
            prims.append(.object([("attributes", .object(attrs)), ("material", .int(materials.count - 1))]))
        }
        var doc: [(String, JSON)] = [
            ("asset", .object([("version", .string("2.0")), ("generator", .string("TilePipeline"))])),
            ("scene", .int(0)), ("scenes", .array([.object([("nodes", .array([.int(0)]))])])),
            ("nodes", .array([.object([("mesh", .int(0)), ("name", .string(name))])])),
            ("meshes", .array([.object([("name", .string(name)), ("primitives", .array(prims))])])),
            ("materials", .array(materials)), ("accessors", .array(blob.accessors)), ("bufferViews", .array(blob.views)),
            ("buffers", .array([.object([("byteLength", .int(blob.data.count))])])),
        ]
        if !images.isEmpty {
            doc += [("images", .array(images)), ("textures", .array(textures)),
                    ("samplers", .array([.object([("magFilter", .int(9729)), ("minFilter", .int(9987))])]))]
        }
        try glb(url, doc, blob)
    }

    /// One mesh, one material: `basePNG` its base colour texture on
    /// TEXCOORD_0, `occlusionPNG` its occlusion texture on TEXCOORD_1, both
    /// embedded. Arrays already in glTF's frame: 3 floats a position or
    /// normal, 2 a UV.
    public static func write(_ url: URL, positions: [Float], normals: [Float], uv0: [Float], uv1: [Float],
                             indices: [UInt32], basePNG: Data, occlusionPNG: Data, name: String = "tile") throws {
        let blob = Blob()
        let pos = blob.attribute(positions, width: 3, bounds: true)
        let nor = blob.attribute(normals, width: 3)
        let t0 = blob.attribute(uv0, width: 2)
        let t1 = blob.attribute(uv1, width: 2)
        let ind = blob.indices(indices)
        let occlusionView = blob.add(occlusionPNG)
        let baseView = blob.add(basePNG)
        let doc: [(String, JSON)] = [
            ("asset", .object([("version", .string("2.0")), ("generator", .string("TilePipeline"))])),
            ("scene", .int(0)), ("scenes", .array([.object([("nodes", .array([.int(0)]))])])),
            ("nodes", .array([.object([("mesh", .int(0)), ("name", .string(name))])])),
            ("meshes", .array([.object([("name", .string(name)), ("primitives", .array([.object([
                ("attributes", .object([("POSITION", .int(pos)), ("NORMAL", .int(nor)), ("TEXCOORD_0", .int(t0)),
                                        ("TEXCOORD_1", .int(t1))])),
                ("indices", .int(ind)), ("material", .int(0)),
            ])]))])])),
            ("materials", .array([.object([
                ("name", .string(name)),
                ("pbrMetallicRoughness", .object([("baseColorTexture", .object([("index", .int(1))])),
                                                  ("metallicFactor", .number(0)), ("roughnessFactor", .number(1))])),
                ("occlusionTexture", .object([("index", .int(0)), ("texCoord", .int(1))])),
            ])])),
            ("textures", .array([.object([("sampler", .int(0)), ("source", .int(0))]),
                                 .object([("sampler", .int(0)), ("source", .int(1))])])),
            ("images", .array([.object([("bufferView", .int(occlusionView)), ("mimeType", .string("image/png")),
                                        ("name", .string("lightmap"))]),
                               .object([("bufferView", .int(baseView)), ("mimeType", .string("image/png")),
                                        ("name", .string("palette"))])])),
            ("samplers", .array([.object([("magFilter", .int(9729)), ("minFilter", .int(9987)), ("wrapS", .int(33071)),
                                          ("wrapT", .int(33071))])])),
            ("accessors", .array(blob.accessors)), ("bufferViews", .array(blob.views)),
            ("buffers", .array([.object([("byteLength", .int(blob.data.count))])])),
        ]
        try glb(url, doc, blob)
    }
}
