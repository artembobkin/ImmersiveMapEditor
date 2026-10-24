import Foundation
import Geometry
import GLTF

/// Brings a downloaded landmark model into the pipeline: the entry of
/// landmarks/credits.json with this id and a `fit`.
///
/// The downloaded file is kept as it came (`fit.source`). Its faces painted
/// with a material in `fit.drop` are removed (a ground plate), the rest is
/// baked into one model (each placement of a component its own copy, a
/// mirrored one turned back to look out, its materials and textures as they
/// came) and cut at its own ground (Z = 0 of the file: what stands below it
/// is the slope of the real street). Its footprint (the faces looking up,
/// above the ground) is fitted to the OSM outline `fit.osm` of the tile
/// `fit.data`: turned, scaled and moved for the largest overlap. The result
/// is written to landmarks/models/<id>/ as a GLB in metres around the
/// outline's centre and a placement.json in the form of Modeling (id, model,
/// origin, altitude_m, replaces), which Imported reads as it reads
/// Modeling's.
public enum Fit {
    static let up = 0.5             // a face whose normal's Z is above this looks up
    static let aboveGround = 1.0    // metres: faces looking up below this are not the footprint

    static func entry(_ ident: String, _ paths: WorkspacePaths) throws -> [String: Any] {
        let url = paths.landmarks.appendingPathComponent("credits.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        for case let m as [String: Any] in root["models"] as? [Any] ?? [] where m["landmark"] as? String == ident && m["fit"] != nil {
            return m
        }
        throw PipelineError("no entry with a fit for \(ident) in landmarks/credits.json")
    }

    /// What stands below Z = 0 cut away, the UVs carried along the cut.
    static func cutAtGround(_ parts: [GLTF.Part]) -> [GLTF.Part] {
        parts.compactMap { part in
            var tris: [SIMD3<Double>] = [], uvs: [SIMD2<Double>] = []
            let hasUV = part.uvs != nil
            for t in 0..<(part.tris.count / 3) {
                let c = Array(part.tris[(t * 3)..<(t * 3 + 3)])
                let u = hasUV ? Array(part.uvs![(t * 3)..<(t * 3 + 3)]) : [SIMD2<Double>](repeating: .zero, count: 3)
                let zs = c.map(\.z)
                if zs.min()! >= 0 {
                    tris += c
                    if hasUV { uvs += u }
                    continue
                }
                if zs.max()! <= 0 { continue }
                var poly: [(SIMD3<Double>, SIMD2<Double>)] = []
                for i in 0..<3 {
                    let (a, ua) = (c[i], u[i]), (b, ub) = (c[(i + 1) % 3], u[(i + 1) % 3])
                    if a.z >= 0 { poly.append((a, ua)) }
                    if (a.z >= 0) != (b.z >= 0) {
                        let s = a.z / (a.z - b.z)
                        poly.append((a + (b - a) * s, ua + (ub - ua) * s))
                    }
                }
                for i in 1..<max(1, poly.count - 1) {
                    tris += [poly[0].0, poly[i].0, poly[i + 1].0]
                    if hasUV { uvs += [poly[0].1, poly[i].1, poly[i + 1].1] }
                }
            }
            if tris.isEmpty { return nil }
            var p = part
            p.tris = tris
            p.uvs = hasUV ? uvs : nil
            return p
        }
    }

    static func footprint(_ parts: [GLTF.Part]) -> Geometry {
        var polys: [Geometry] = []
        for part in parts {
            for t in 0..<(part.tris.count / 3) {
                let a = part.tris[t * 3], b = part.tris[t * 3 + 1], c = part.tris[t * 3 + 2]
                let n = (b - a).cross(c - a)
                if n.length > 0 && abs(n.z / n.length) > up && max(a.z, b.z, c.z) > aboveGround {
                    var g = Geometry.polygon([P2(a.x, a.y), P2(b.x, b.y), P2(c.x, c.y)])
                    if !g.isValid { g = g.buffer(0) }
                    if g.area > 0.01 { polys.append(g.buffer(0.02)) }
                }
            }
        }
        return .unaryUnion(polys)
    }

    /// Angle (degrees), scale and offset taking `model` onto `outline`, about
    /// the model's centroid, and the overlap reached (intersection over
    /// union). Coordinate descent from the centroids laid on each other.
    static func fit(_ model: Geometry, _ outline: Geometry) -> ([Double], Double, P2) {
        let mc = model.centroid.xy, oc = outline.centroid.xy
        func placed(_ p: [Double]) -> Geometry {
            model.rotate(p[0], origin: mc).scale(p[1], p[1], origin: mc).translate(oc.x - mc.x + p[2], oc.y - mc.y + p[3])
        }
        func overlap(_ p: [Double]) -> Double {
            let g = placed(p)
            return g.intersection(outline).area / g.union(outline).area
        }
        var best = stride(from: -180, to: 180, by: 2).map { [Double($0), 1, 0, 0] }.max { overlap($0) < overlap($1) }!
        var steps = [1.0, 0.02, 2.0, 2.0]
        for _ in 0..<8 {
            for _ in 0..<20 {
                var moved = false
                for k in 0..<4 {
                    for sign in [-1.0, 1.0] {
                        var p = best
                        p[k] += sign * steps[k]
                        if overlap(p) > overlap(best) {
                            best = p
                            moved = true
                        }
                    }
                }
                if !moved { break }
            }
            steps = steps.map { $0 / 2 }
        }
        return (best, overlap(best), oc - mc)
    }

    public static func run(_ ident: String, _ paths: WorkspacePaths) throws {
        let spec = try entry(ident, paths)["fit"] as? [String: Any] ?? [:]
        let tile = try Tile(folder: paths.resolve(spec["data"] as? String ?? ""))
        let osm = try Osm(tile)
        let ref = (spec["osm"] as? String ?? "").split(separator: "/")
        guard ref.count == 2, let num = Int64(ref[1]),
              let outline = osm.areas().first(where: { $0.kind == String(ref[0]) && $0.id == num })?.shape
        else { throw PipelineError("no OSM outline \(spec["osm"] ?? "") in \(spec["data"] ?? "")") }
        let drop = Set(spec["drop"] as? [String] ?? [])
        let all = try GLTF.primitives(paths.resolve(spec["source"] as? String ?? ""))
        var parts = cutAtGround(all.filter { !drop.contains($0.material.name) && !$0.tris.isEmpty })
        let model = footprint(parts)
        let (p, iou, centres) = fit(model, outline)
        let (angle, s) = (p[0], p[1])
        print(String(format: "[fit] %@: angle %.2f deg, scale %.3f, offset %.2f %.2f m, overlap %.3f", ident, angle, s,
                     p[2], p[3], iou))
        // Model metres around the outline's centre: turned and scaled about
        // the footprint's centroid, then moved onto the outline.
        let mc = model.centroid.xy, oc = outline.centroid.xy
        let shift = SIMD3(mc.x + centres.x + p[2] - oc.x, mc.y + centres.y + p[3] - oc.y, 0)
        let r = angle * .pi / 180
        for i in parts.indices {
            parts[i].tris = parts[i].tris.map { v in
                let d = (v - SIMD3(mc.x, mc.y, 0)) * s
                return SIMD3(d.x * cos(r) - d.y * sin(r), d.x * sin(r) + d.y * cos(r), d.z) + shift
            }
        }
        let folder = paths.landmarks.appendingPathComponent("models/\(ident)")
        let name = ident.replacingOccurrences(of: "-", with: "_") + ".glb"
        try GLTF.writeModel(folder.appendingPathComponent(name), parts, name: ident)
        let (lon, lat) = tile.lonLat(oc)
        let top = parts.flatMap { $0.tris.map(\.z) }.max() ?? 0
        let triangles = parts.reduce(0) { $0 + $1.tris.count / 3 }
        func round(_ v: Double, _ d: Double) -> Double { (v * d).rounded() / d }
        let placement: [String: Any] = [
            "id": ident, "model": name, "origin": ["latitude": round(lat, 1e7), "longitude": round(lon, 1e7)],
            "altitude_m": 0.0, "replaces": ["\(tile.z)": [spec["osm"] as? String ?? ""]],
            "fit": ["angle_deg": round(angle, 1e3), "scale": round(s, 1e4), "overlap": round(iou, 1e3),
                    "height_m": round(top, 1e2), "triangles": triangles],
        ]
        try Export.write(placement, folder.appendingPathComponent("placement.json"))
        print(String(format: "[fit] wrote %@, %d triangles, %.1f m high", folder.appendingPathComponent(name).path, triangles, top))
    }
}
