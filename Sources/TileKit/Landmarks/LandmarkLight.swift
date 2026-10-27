import Foundation
import Geometry
import GLTF

/// A landmark's model lit as the engine will light it, alone: its faces in
/// their palette tones (each wall's tone by its side against the sun, as the
/// tile build paints them), its light map baked over the model and a white
/// ground around it with the tile's settings, and each corner's place in
/// that map. What the editor's Preview shows for a landmark without
/// building the tile.
public enum LandmarkLight {
    /// Ground around the model in the bake, so its walls get their bounce
    /// and the light at its foot is the open ground's.
    public static let margin = 30.0
    /// Metres a texel: the tile's own (1024 texels over a z15 tile in
    /// Moscow), so the preview shows the light as the engine will have it.
    /// Finer would look better and lie: the bake's noise, spread over 0.67
    /// m on the tile, shows as streaks down a wall at 0.1 m.
    public static let texel = 0.674
    public static let maxSize = 2048

    public struct Result {
        /// Corners (X east, Y north, Z up), three a triangle.
        public var positions: [Double]
        /// The sRGB bytes of each triangle's colour, three a triangle.
        public var colours: [UInt8]
        /// TEXCOORD_1 of each corner, V up, in `bounds`.
        public var uv1: [Double]
        /// The light map's RGB bytes, `size` square, row 0 on the north.
        public var light: [UInt8]
        public var size: Int
        public var bounds: (Double, Double, Double, Double)
        /// Toward the sun in the view's axes (X east, Y up, Z south) for the
        /// engine's shadow, nil when the sun is baked into the light.
        public var sun: SIMD3<Float>?
        public var triangles: Int { colours.count / 3 }
    }

    /// Reads the model and bakes its light with `settings` (its size set by
    /// the model: `texel` metres a texel).
    public static func bake(_ glb: URL, settings: Lighting.Settings) throws -> Result {
        var tris = Triangles()
        var colours: [UInt8] = []
        var lo = V3(.infinity, .infinity, .infinity), hi = -lo
        for part in try GLTF.primitives(glb) {
            let name = part.material.name
            let factor = part.material.factor
            for t in stride(from: 0, to: part.tris.count - 2, by: 3) {
                let p = [part.tris[t], part.tris[t + 1], part.tris[t + 2]].map { V3($0.x, $0.y, $0.z) }
                let n = (p[1] - p[0]).cross(p[2] - p[0])
                guard n.length > 1e-12 else { continue }
                for q in p {
                    lo = V3(min(lo.x, q.x), min(lo.y, q.y), min(lo.z, q.z))
                    hi = V3(max(hi.x, q.x), max(hi.y, q.y), max(hi.z, q.z))
                }
                tris.append(p, [P2(0, 0), P2(0, 0), P2(0, 0)], .whole, (0, 0))
                colours += colour(name, factor, normal: n.normalized)
            }
        }
        guard tris.count > 0 else { throw Failure("no triangles in \(glb.lastPathComponent)") }
        spanWalls(&tris)
        // A square around the model with the margin, its light map at the
        // texel asked, capped.
        let cx = (lo.x + hi.x) / 2, cy = (lo.y + hi.y) / 2
        let half = max(hi.x - lo.x, hi.y - lo.y) / 2 + margin
        let size = min(maxSize, max(256, Int((2 * half / texel).rounded(.up))))
        let bounds = (cx - half, cy - half, cx + half, cy + half)
        // The scene: the model and the white ground under it, a little
        // beyond the map so nothing at its edge looks out into the void.
        var scene = tris.pos
        let g = half * 1.5, z = min(0, lo.z)
        scene += [cx - g, cy - g, z, cx + g, cy - g, z, cx + g, cy + g, z,
                  cx - g, cy - g, z, cx + g, cy + g, z, cx - g, cy + g, z]
        var s = settings
        s.size = size
        let irradiance = try Lighting.bake(scene, bounds: bounds, size: size, settings: s)
        let light = Lighting.shape(irradiance, s)
        let uv1 = Lighting.lightUVs(tris, bounds: bounds, size: size)
        if let dump = ProcessInfo.processInfo.environment["LANDMARK_LIGHT_DUMP"] {
            try? PNG.encode(light, width: size, height: size, channels: 3).write(to: URL(fileURLWithPath: dump))
        }
        let a = s.sunAzimuth * .pi / 180, e = s.sunElevation * .pi / 180
        let sun = s.sun ? nil : SIMD3<Float>(Float(sin(a) * cos(e)), Float(sin(e)), Float(-cos(a) * cos(e)))
        return Result(positions: tris.pos, colours: colours, uv1: uv1, light: light, size: size, bounds: bounds, sun: sun)
    }

    /// A face's colour: its material's palette colour sided by the sun when
    /// the palette has tones of it, the material's own factor otherwise (a
    /// model not made from a recipe).
    static func colour(_ name: String, _ factor: [Double], normal n: V3) -> [UInt8] {
        let sided = name.isEmpty ? nil : Palette.hex("\(name).\(Palette.side(n.x, n.y))") ?? Palette.hex(name)
        if let hex = sided {
            let (r, g, b) = Palette.rgb(hex)
            return [UInt8(r), UInt8(g), UInt8(b)]
        }
        return (0..<3).map { UInt8(min(max(factor.count > $0 ? factor[$0] : 1, 0), 1) * 255 + 0.5) }
    }

    /// Each wall's span: the height of the plane it is part of (the faces on
    /// one plane that touch), so the whole wall shades from its foot up, as
    /// the tile build spans an imported model's walls.
    static func spanWalls(_ tris: inout Triangles) {
        let n = tris.count
        var normals: [V3] = [], offsets: [Double] = []
        for t in 0..<n {
            let v = tris.normal(t).normalized
            normals.append(v)
            offsets.append(v.dot(tris.corner(t, 0)))
        }
        // Planes by their normal and offset, rounded.
        var plane: [String: [Int]] = [:]
        for t in 0..<n where abs(normals[t].z) < Lighting.wallLimit {
            let k = String(format: "%.2f,%.2f,%.1f", normals[t].x, normals[t].y, offsets[t])
            plane[k, default: []].append(t)
        }
        for (_, faces) in plane {
            var lo = Double.infinity, hi = -Double.infinity
            for t in faces {
                for i in 0..<3 {
                    let z = tris.corner(t, i).z
                    lo = min(lo, z)
                    hi = max(hi, z)
                }
            }
            for t in faces {
                tris.wall[t * 2] = lo
                tris.wall[t * 2 + 1] = hi
            }
        }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
        init(_ s: String) { description = s }
    }
}
