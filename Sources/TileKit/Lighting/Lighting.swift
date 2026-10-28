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
        /// How deep the shade goes: 1 to the shade colour, 0 no shading at
        /// all (the user, 2026-10-28: a strength for the light).
        public var depth = 1.0
        /// What light is gathered: the sky with its bounces ("sky"), or only
        /// how open each surface is within `aoRadius` metres ("ao").
        public var mode = "sky"
        public var aoRadius = 8.0
        /// A sun baked in, from a compass bearing (`SUN_FROM` by default)
        /// at a height in degrees: off by default, the engine casting the
        /// sun's shadows itself.
        public var sun = false
        public var sunAzimuth = 225.0
        public var sunElevation = 45.0
        public var sunStrength = 1.0
        public var skyStrength = 1.0
        /// A landmark alone (Preview): its walls in the palette's tones by
        /// their side against `Palette.sunFrom`, as the tile paints them,
        /// or every face in its plain colour (the user, 2026-10-28: a way
        /// to turn the directed light off). Not stored with a tile.
        public var sidedTones = true

        public init() {}

        /// The baker's options from these settings.
        var options: LightBaker.Options {
            var o = LightBaker.Options()
            o.mode = mode == "ao" ? .ambientOcclusion : .sky
            o.radius = Float(aoRadius)
            if sun {
                let az = sunAzimuth * .pi / 180, el = sunElevation * .pi / 180
                o.sun = SIMD3(Float(sin(az) * cos(el)), Float(cos(az) * cos(el)), Float(sin(el)))
            }
            o.sunStrength = Float(sunStrength)
            o.skyStrength = Float(skyStrength)
            return o
        }

        /// The settings as bake/settings.json has them, with the light map's
        /// size in pixels it gave (`light_map_px`, for the reader only).
        public func json(lightMapPixels: Int) -> [String: Any] {
            ["size": size, "samples": samples, "bounces": bounces, "lit": lit, "shade": shade, "gamma": gamma, "depth": depth,
             "mode": mode, "ao_radius": aoRadius, "sun": sun, "sun_azimuth": sunAzimuth, "sun_elevation": sunElevation,
             "sun_strength": sunStrength, "sky_strength": skyStrength, "light_map_px": lightMapPixels]
        }

        /// Read from bake/settings.json: what it lacks keeps its default.
        public init(json: [String: Any]) {
            if let v = json["size"] as? Int { size = v }
            if let v = json["samples"] as? Int { samples = v }
            if let v = json["bounces"] as? Int { bounces = v }
            if let v = json["lit"] as? [Double], v.count == 3 { lit = v }
            if let v = json["shade"] as? [Double], v.count == 3 { shade = v }
            if let v = json["gamma"] as? Double { gamma = v }
            if let v = json["depth"] as? Double { depth = v }
            if let v = json["mode"] as? String { mode = v }
            if let v = json["ao_radius"] as? Double { aoRadius = v }
            if let v = json["sun"] as? Bool { sun = v }
            if let v = json["sun_azimuth"] as? Double { sunAzimuth = v }
            if let v = json["sun_elevation"] as? Double { sunElevation = v }
            if let v = json["sun_strength"] as? Double { sunStrength = v }
            if let v = json["sky_strength"] as? Double { skyStrength = v }
        }
    }

    /// The light reaching the topmost surface over each texel, row 0 on the
    /// north. `tris` hold the geometry of the margin around the region too,
    /// so the light at the edges is what a neighbour tile sees.
    public static func bake(_ tris: [Double], bounds: (Double, Double, Double, Double), size: Int,
                            settings: Settings) throws -> [Float] {
        let started = Date()
        let what = settings.mode == "ao" ? String(format: "ambient occlusion %.0f m", settings.aoRadius)
            : "sky, \(settings.bounces) bounces"
        let sun = settings.sun ? String(format: ", sun from %.0f° at %.0f°", settings.sunAzimuth, settings.sunElevation) : ""
        let detail = "\(size) px, \(settings.samples) samples, " + what + sun
        Progress.report("Baking the light", fraction: 0, detail: detail)
        let light = try LightBaker.bake(triangles: tris.map(Float.init), bounds: bounds, size: size, samples: settings.samples,
                                        bounces: settings.bounces, options: settings.options) {
            Progress.report("Baking the light", fraction: $0, detail: detail)
        }
        print(String(format: "[bake] %d triangles, %@ in %.1f s", tris.count / 9, detail, Date().timeIntervalSince(started)))
        return ProcessInfo.processInfo.environment["LIGHT_NO_DENOISE"] == nil ? denoise(light, size: size) : light
    }

    /// The bake's grain smoothed. A path-traced texel keeps a few percent of
    /// chance, and the preview showed it (the user, 2026-10-28): a wall
    /// takes one column of texels along its length, so the grain ran down
    /// it in stripes, and a roof seen at a slant smeared it into streaks.
    /// A bilateral filter over 5 × 5 texels: a neighbour counts by its
    /// distance and by how close its value is, within `range` of the open
    /// ground's light, so the grain averages out while the shade beside a
    /// wall (a step of far more) stays where it is.
    public static func denoise(_ irradiance: [Float], size: Int, range: Float = 0.06) -> [Float] {
        guard size >= 5, irradiance.count == size * size else { return irradiance }
        let sorted = irradiance.sorted()
        let reference = sorted[Int(0.75 * Double(sorted.count - 1))]
        let sigma = max(range * reference, 1e-6)
        let spatial: [Float] = (-2...2).flatMap { dy in (-2...2).map { dx in expf(-Float(dx * dx + dy * dy) / (2 * 1.2 * 1.2)) } }
        var out = irradiance
        irradiance.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                DispatchQueue.concurrentPerform(iterations: size) { y in
                    for x in 0..<size {
                        let v = src[y * size + x]
                        var sum: Float = 0, weight: Float = 0, k = 0
                        for dy in -2...2 {
                            let yy = y + dy
                            for dx in -2...2 {
                                defer { k += 1 }
                                let xx = x + dx
                                guard xx >= 0, xx < size, yy >= 0, yy < size else { continue }
                                let u = src[yy * size + xx], d = (u - v) / sigma
                                let w = spatial[k] * expf(-0.5 * d * d)
                                sum += u * w
                                weight += w
                            }
                        }
                        dst[y * size + x] = weight > 0 ? sum / weight : v
                    }
                }
            }
        }
        return out
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
        let l = settings.lit, depth = min(max(settings.depth, 0), 1)
        let s = (0..<3).map { l[$0] + (settings.shade[$0] - l[$0]) * depth }
        for (i, v) in irradiance.enumerated() {
            let t = pow(min(max(Double(v) / max(reference, 1e-6), 0), 1), gamma)
            for k in 0..<3 {
                out[i * 3 + k] = UInt8(min(max(s[k] + (l[k] - s[k]) * t, 0), 1) * 255 + 0.5)
            }
        }
        return out
    }

    /// Texels a wall reaches past its line for its light: outside at its
    /// foot, inside at its top. One texel sat in the dark seam the ground
    /// and the roof have along every wall (the corner shut in), and the
    /// seam spread down the whole wall (the user, 2026-10-28, in Preview).
    static let wallReach = 2.0
    /// A horizontal face of a facade's relief (a band's top, a sill, a
    /// cornice) is at most this many texels across in plan.
    static let reliefWidth = 1.5
    /// A wall a relief face can sit on is at least this tall.
    static let reliefWallSpan = 3.0

    /// TEXCOORD_1 of every corner (6 a triangle, V up). A face takes its own
    /// place in plan, a roof slope too. A wall takes the ground `wallReach`
    /// texels outside it at its foot and the surface as far inside it at
    /// its top, so it shades from its foot up: over the whole wall it is
    /// part of (its span), else over its own height. A small horizontal
    /// face sitting on a wall (its relief: a band's top, a sill, a cornice)
    /// takes the wall's light at its height instead of its own place in
    /// plan, which lies on the wall's line where the map steps from the
    /// ground to the roof and striped every storey (the user, 2026-10-28).
    public static func lightUVs(_ m: Triangles, bounds: (Double, Double, Double, Double), size: Int) -> [Double] {
        let (x0, y0, x1, _) = bounds
        let w = x1 - x0
        let d = w / Double(size)
        var out = [Double](repeating: 0, count: m.count * 6)
        // The walls a relief face may sit on, by their corners.
        struct Key: Hashable { let x, y, z: Int64 }
        func key(_ p: V3) -> Key { Key(x: Int64((p.x * 1000).rounded()), y: Int64((p.y * 1000).rounded()), z: Int64((p.z * 1000).rounded())) }
        var wallsAt: [Key: [Int]] = [:]
        for t in 0..<m.count where abs(m.normal(t).normalized.z) < wallLimit && m.wall[t * 2 + 1] - m.wall[t * 2] >= reliefWallSpan {
            for i in 0..<3 { wallsAt[key(m.corner(t, i)), default: []].append(t) }
        }
        for t in 0..<m.count {
            let n = m.normal(t).normalized
            var wall = abs(n.z) < wallLimit
            var h = P2(n.x, n.y).length > 1e-6 ? P2(n.x, n.y).normalized : P2(n.x, n.y) / 1e-6
            let zs = (0..<3).map { m.corner(t, $0).z }
            var spanned = m.wall[t * 2 + 1] > m.wall[t * 2]
            var lo = spanned ? m.wall[t * 2] : zs.min()!
            var span = spanned ? m.wall[t * 2 + 1] - m.wall[t * 2] : zs.max()! - zs.min()!
            // The wall's plane a relief face is moved onto, by its offset along h.
            var plane: Double?
            if !wall && !wallsAt.isEmpty {
                let xs = (0..<3).map { m.corner(t, $0).x }, ys = (0..<3).map { m.corner(t, $0).y }
                if max(xs.max()! - xs.min()!, ys.max()! - ys.min()!) < reliefWidth * d {
                    var best: Int?, bestSpan = 0.0
                    for i in 0..<3 {
                        for c in wallsAt[key(m.corner(t, i))] ?? [] {
                            let s = m.wall[c * 2 + 1] - m.wall[c * 2]
                            if s > bestSpan { best = c; bestSpan = s }
                        }
                    }
                    if let c = best {
                        let wn = m.normal(c).normalized
                        wall = true
                        h = P2(wn.x, wn.y).normalized
                        spanned = true
                        lo = m.wall[c * 2]
                        span = bestSpan
                        plane = h.x * m.corner(c, 0).x + h.y * m.corner(c, 0).y
                    }
                }
            }
            // A flat face's corners pulled half a texel toward its middle, so
            // its edge samples its own texel and not the one outside it (on a
            // roof's rim that is the dark seam at the wall's foot, blended in
            // by the filter as a dark band along the rim: the user, 2026-10-28).
            let mid = (0..<3).reduce(P2.zero) { $0 + P2(m.corner(t, $1).x, m.corner(t, $1).y) } / 3
            for i in 0..<3 {
                let c = m.corner(t, i)
                var x = c.x, y = c.y
                if !wall {
                    let v = mid - P2(x, y), len = v.length
                    if len > 1e-9 {
                        let pull = min(len, d * 0.5)
                        x += v.x / len * pull
                        y += v.y / len * pull
                    }
                }
                if let plane {
                    let off = h.x * x + h.y * y - plane
                    x -= h.x * off
                    y -= h.y * off
                }
                if wall && span > 1e-4 {
                    let s = min(max((c.z - lo) / span, 0), 1)
                    x += h.x * d * wallReach * (1 - 2 * s)
                    y += h.y * d * wallReach * (1 - 2 * s)
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
