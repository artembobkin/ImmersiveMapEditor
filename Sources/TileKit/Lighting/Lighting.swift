import Foundation
import Geometry
import LightBaker

/// The light map: the tile seen from straight above, every surface white,
/// lit by the sky (`bake`, on the GPU through LightBaker), and TEXCOORD_1,
/// each corner's place in it (`lightUVs`). See TilePipeline's CLAUDE.md,
/// "The output".
public enum Lighting {
    /// The light map is RGB: ASTC 8x8 costs the same for colour as for grey.
    /// Open ground takes lit, the darkest corner shade, a courtyard in
    /// between: warm light, cool shade.
    static let lit = (1.0, 0.985, 0.95)
    static let shade = (0.40, 0.42, 0.56)
    static let gamma = 1.6      // above 1 deepens the shade near walls and in courtyards
    static let wallLimit = 0.15 // a face whose normal is this close to level is a wall
    static let bounces = 3

    /// What a bake can be told: the light map's density, the bake's samples
    /// and bounces, and how its irradiance turns into the multiplier (`lit`,
    /// `shade`, `gamma`). The defaults are the constants above. Stored as
    /// bake/settings.json beside a built tile, so its light can be baked
    /// again (Bake).
    public struct Settings: Equatable {
        /// Light map texels over the tile's width. The light map itself is
        /// as much larger as it reaches over the tile.
        public var size = 1024
        public var samples = 256
        public var bounces = Lighting.bounces
        public var lit = [Lighting.lit.0, Lighting.lit.1, Lighting.lit.2]
        public var shade = [Lighting.shade.0, Lighting.shade.1, Lighting.shade.2]
        public var gamma = Lighting.gamma

        public init() {}

        /// The settings as bake/settings.json has them, with the light map's
        /// size in pixels it gave (`light_map_px`, for the reader only).
        public func json(lightMapPixels: Int) -> [String: Any] {
            ["size": size, "samples": samples, "bounces": bounces, "lit": lit, "shade": shade, "gamma": gamma,
             "light_map_px": lightMapPixels]
        }

        /// Read from bake/settings.json: what it lacks keeps its default.
        public init(json: [String: Any]) {
            if let v = json["size"] as? Int { size = v }
            if let v = json["samples"] as? Int { samples = v }
            if let v = json["bounces"] as? Int { bounces = v }
            if let v = json["lit"] as? [Double], v.count == 3 { lit = v }
            if let v = json["shade"] as? [Double], v.count == 3 { shade = v }
            if let v = json["gamma"] as? Double { gamma = v }
        }
    }

    /// The light reaching the topmost surface over each texel, row 0 on the
    /// north. `tris` hold the geometry of the margin around the region too,
    /// so the light at the edges is what a neighbour tile sees.
    public static func bake(_ tris: [Double], bounds: (Double, Double, Double, Double), size: Int,
                            samples: Int, bounces: Int) throws -> [Float] {
        let started = Date()
        let light = try LightBaker.bake(triangles: tris.map(Float.init), bounds: bounds, size: size, samples: samples,
                                        bounces: bounces)
        print(String(format: "[bake] %d triangles, %d px, %d samples, %d bounces in %.1f s", tris.count / 9, size,
                     samples, bounces, Date().timeIntervalSince(started)))
        return light
    }

    /// Irradiance to the light map's multiplier, RGB bytes: open ground lit,
    /// the darkest corners shade, never black.
    public static func shape(_ irradiance: [Float], _ settings: Settings = Settings()) -> [UInt8] {
        let gamma = settings.gamma
        let sorted = irradiance.sorted()
        // numpy's percentile: linear between the two nearest ranks.
        let rank = 0.75 * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down)), hi = min(sorted.count - 1, lo + 1)
        let reference = Double(sorted[lo]) + (Double(sorted[hi]) - Double(sorted[lo])) * (rank - Double(lo))
        var out = [UInt8](repeating: 0, count: irradiance.count * 3)
        let s = settings.shade, l = settings.lit
        for (i, v) in irradiance.enumerated() {
            let t = pow(min(max(Double(v) / max(reference, 1e-6), 0), 1), gamma)
            for k in 0..<3 {
                out[i * 3 + k] = UInt8(min(max(s[k] + (l[k] - s[k]) * t, 0), 1) * 255 + 0.5)
            }
        }
        return out
    }

    /// TEXCOORD_1 of every corner (6 a triangle, V up). A face takes its own
    /// place in plan, a roof slope too. A wall takes the ground a texel
    /// outside it at its foot and the surface a texel inside it at its top, so
    /// it shades from its foot up: over the whole wall it is part of (its
    /// span), else over its own height.
    public static func lightUVs(_ m: Triangles, bounds: (Double, Double, Double, Double), size: Int) -> [Double] {
        let (x0, y0, x1, _) = bounds
        let w = x1 - x0
        let d = w / Double(size)
        var out = [Double](repeating: 0, count: m.count * 6)
        for t in 0..<m.count {
            let n = m.normal(t).normalized
            let wall = abs(n.z) < wallLimit
            let h = P2(n.x, n.y).length > 1e-6 ? P2(n.x, n.y).normalized : P2(n.x, n.y) / 1e-6
            let zs = (0..<3).map { m.corner(t, $0).z }
            let spanned = m.wall[t * 2 + 1] > m.wall[t * 2]
            let lo = spanned ? m.wall[t * 2] : zs.min()!
            let span = spanned ? m.wall[t * 2 + 1] - m.wall[t * 2] : zs.max()! - zs.min()!
            for i in 0..<3 {
                let c = m.corner(t, i)
                var x = c.x, y = c.y
                if wall && span > 1e-4 {
                    let s = min(max((c.z - lo) / span, 0), 1)
                    x += h.x * d * (1 - 2 * s)
                    y += h.y * d * (1 - 2 * s)
                }
                // Clamped: a wall on the edge would reach a texel outside, and
                // every UV stays within 0..1.
                out[t * 6 + i * 2] = min(max((x - x0) / w, 0), 1)
                out[t * 6 + i * 2 + 1] = min(max((y - y0) / w, 0), 1)
            }
        }
        return out
    }
}
