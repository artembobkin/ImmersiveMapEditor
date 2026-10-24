import Foundation

/// Checks a built tile against the rules of TilePipeline's CLAUDE.md ("The
/// model file: GLB", "Fitting the engine") and writes validation.json next
/// to it. Reads the GLB on its own, not through the writer, so it checks
/// what is on disk.
public enum Validate {
    /// Buildings are kept whole and may reach over the edge by as much as
    /// the build reports (overhang_m), never more than this.
    static let maxOverhang = 200.0

    public struct Check {
        public let name: String
        public let ok: Bool
        public let detail: String
    }

    public struct Result {
        public let model: String
        public let triangles: Int
        public let bytes: Int
        public let checks: [Check]
        public var ok: Bool { checks.allSatisfy(\.ok) }
    }

    public static func tile(_ folder: URL) throws -> Result {
        var checks: [Check] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { checks.append(Check(name: name, ok: ok, detail: detail)) }
        func json(_ name: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(name))) as? [String: Any] ?? [:]
        }
        let placement = try json("placement.json"), meta = try json("metadata.json")
        let half = (meta["size_m"] as? Double ?? 0) / 2
        let model = placement["model"] as? String ?? ""
        let data = try Data(contentsOf: folder.appendingPathComponent(model))
        func u32(_ at: Int) -> Int { Int(data.subdata(in: at..<(at + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) }
        guard data.count > 20, u32(0) == 0x4654_6C67, u32(4) == 2, u32(8) == data.count else {
            throw PipelineError("\(model) is not a glTF 2.0 binary")
        }
        var at = 12
        var gltf: [String: Any] = [:]
        var binary = Data()
        while at + 8 <= data.count {
            let size = u32(at), kind = u32(at + 4)
            let body = data.subdata(in: (at + 8)..<(at + 8 + size))
            if kind == 0x4E4F_534A { gltf = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:] }
            if kind == 0x004E_4942 { binary = body }
            at += 8 + size
        }
        func list(_ k: String) -> [[String: Any]] { gltf[k] as? [[String: Any]] ?? [] }
        check("placement", ["id", "model", "origin", "altitude_m"].allSatisfy { placement[$0] != nil })
        let meshes = list("meshes")
        let prims = meshes.first?["primitives"] as? [[String: Any]] ?? []
        check("one mesh, one primitive", meshes.count == 1 && prims.count == 1)
        let prim = prims.first ?? [:]
        let attrs = prim["attributes"] as? [String: Int] ?? [:]
        check("attributes", Set(attrs.keys) == ["POSITION", "NORMAL", "TEXCOORD_0", "TEXCOORD_1"], attrs.keys.sorted().description)
        check("triangles, indexed", (prim["mode"] as? Int ?? 4) == 4 && prim["indices"] != nil)
        let accessors = list("accessors")
        let indices = accessors[prim["indices"] as? Int ?? 0]
        let triangles = (indices["count"] as? Int ?? 0) / 3
        check("indices u32 or smaller", [5121, 5123, 5125].contains(indices["componentType"] as? Int ?? 0))
        let mats = list("materials")
        check("one material", mats.count == 1)
        let m = mats.first ?? [:]
        let pbr = m["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let base = pbr["baseColorTexture"] as? [String: Any], occ = m["occlusionTexture"] as? [String: Any]
        check("palette on TEXCOORD_0", base != nil && (base?["texCoord"] as? Int ?? 0) == 0)
        check("light map on TEXCOORD_1", occ != nil && (occ?["texCoord"] as? Int ?? 0) == 1)
        check("base colour factor white", (pbr["baseColorFactor"] as? [Double] ?? [1, 1, 1, 1]) == [1, 1, 1, 1])
        check("nothing else in the material", m["normalTexture"] == nil && m["emissiveTexture"] == nil
              && (m["alphaMode"] as? String ?? "OPAQUE") == "OPAQUE" && pbr["metallicRoughnessTexture"] == nil)
        let images = list("images")
        check("two embedded PNG", images.count == 2 && images.allSatisfy { $0["mimeType"] as? String == "image/png" && $0["bufferView"] != nil })
        check("no cameras, lights, skins, animations", gltf["cameras"] == nil && gltf["skins"] == nil
              && gltf["animations"] == nil && (gltf["extensionsUsed"] as? [Any] ?? []).isEmpty)
        let pos = accessors[attrs["POSITION"] ?? 0]
        let lo = pos["min"] as? [Double] ?? [0, 0, 0], hi = pos["max"] as? [Double] ?? [0, 0, 0]
        let overhang = (meta["statistics"] as? [String: Any])?["overhang_m"] as? Double ?? 40
        check("overhang within limits", overhang <= maxOverhang, "\(overhang) m")
        let eps = max(overhang, 0) + 0.05
        check("inside the tile and its margin", lo[0] >= -half - eps && hi[0] <= half + eps && lo[2] >= -half - eps
              && hi[2] <= half + eps,
              String(format: "x %.2f..%.2f, z %.2f..%.2f, half %.2f", lo[0], hi[0], lo[2], hi[2], half))
        check("nothing below the ground", lo[1] >= -0.01, String(format: "lowest %.3f m", lo[1]))
        let views = list("bufferViews")
        for key in ["TEXCOORD_0", "TEXCOORD_1"] {
            let acc = accessors[attrs[key] ?? 0]
            let view = views[acc["bufferView"] as? Int ?? 0]
            let start = (view["byteOffset"] as? Int ?? 0) + (acc["byteOffset"] as? Int ?? 0)
            let count = (acc["count"] as? Int ?? 0) * 2
            let uv = binary.subdata(in: start..<(start + count * 4)).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let a = uv.min() ?? 0, b = uv.max() ?? 0
            check("\(key) inside 0..1", a >= -1e-4 && b <= 1 + 1e-4, String(format: "%.4f..%.4f", a, b))
        }
        let result = Result(model: model, triangles: triangles, bytes: data.count, checks: checks)
        let out: [String: Any] = [
            "model": model, "triangles": triangles, "height_m": (hi[1] * 10).rounded() / 10, "glb_bytes": data.count,
            "ok": result.ok, "checks": checks.map { ["check": $0.name, "ok": $0.ok, "detail": $0.detail] },
        ]
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("validation.json"))
        return result
    }
}
