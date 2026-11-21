import AppKit
import Geometry
import GLTF
import MetalKit
import simd
import TileKit

/// The models a landmark renderer draws, made from a GLB: plain (each
/// part with its texture or colour) and lit (each face with its palette
/// colour, for the preview's sun and shadow).
extension LandmarkRenderer {
    /// A model for the light: every triangle with its palette colour, one
    /// buffer.
    struct LitModel {
        let vertices: MTLBuffer
        let count: Int
        let ground: MTLBuffer
        /// The axes beside the model: three arrows (a bar and a cone each,
        /// triangles) east, north and up from a corner outside its bounds
        /// on the ground, so they never cross it (the user, 2026-10-29),
        /// `axisCounts` vertices each; and the labels' places in the
        /// scene: X E, Y N and Z at the tips.
        let axes: MTLBuffer
        let axisCounts: [Int]
        let labels: [(String, SIMD3<Float>)]
        /// The model's corners, three a triangle, for what hides a label.
        let corners: [SIMD3<Float>]

        /// Whether the segment from `a` to `b` meets a triangle of the model
        /// (a label's place hidden behind it; the user, 2026-10-29).
        func hidden(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Bool {
            let d = b - a
            var t = 0
            while t + 2 < corners.count {
                let p0 = corners[t], e1 = corners[t + 1] - p0, e2 = corners[t + 2] - p0
                t += 3
                let h = simd_cross(d, e2), det = simd_dot(e1, h)
                if abs(det) < 1e-7 { continue }
                let inv = 1 / det, s = a - p0
                let u = inv * simd_dot(s, h)
                if u < 0 || u > 1 { continue }
                let q = simd_cross(s, e1)
                let v = inv * simd_dot(d, q)
                if v < 0 || u + v > 1 { continue }
                let k = inv * simd_dot(e2, q)
                if k > 0.001 && k < 0.98 { return true }
            }
            return false
        }
        let centre: SIMD3<Double>
        let size: SIMD3<Double>
        let triangles: Int

        static func make(_ r: LandmarkTones.Result, device: MTLDevice) throws -> LitModel {
            var v: [Float] = []
            v.reserveCapacity(r.triangles * 33)
            var lo = SIMD3<Double>(repeating: .infinity), hi = -lo
            var corners: [SIMD3<Float>] = []
            corners.reserveCapacity(r.triangles * 3)
            for t in 0..<r.triangles {
                // The build's east, north, up to the view's east, up, south.
                let p = (0..<3).map { SIMD3(r.positions[t * 9 + $0 * 3], r.positions[t * 9 + $0 * 3 + 2], -r.positions[t * 9 + $0 * 3 + 1]) }
                for k in 0..<3 { corners.append(SIMD3<Float>(p[k])) }
                let n = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
                let c = (0..<3).map { Float(r.colours[t * 3 + $0]) / 255 }
                for k in 0..<3 {
                    lo = simd_min(lo, p[k])
                    hi = simd_max(hi, p[k])
                    // Eleven floats a vertex, the last two unused.
                    v += [Float(p[k].x), Float(p[k].y), Float(p[k].z), Float(n.x), Float(n.y), Float(n.z), c[0], c[1], c[2], 0, 0]
                }
            }
            guard !v.isEmpty, let buffer = device.makeBuffer(bytes: v, length: v.count * 4) else { throw TileModel.Failure.glb("no triangles") }
            let centre = (lo + hi) / 2
            let radius = Float(max(hi.x - lo.x, hi.z - lo.z) * 1.5 + 40)
            let (gx, gy, gz) = (Float(centre.x), Float(lo.y) - 0.02, Float(centre.z))
            var g: [Float] = []
            for (x, z) in [(-1, -1), (-1, 1), (1, 1), (-1, -1), (1, 1), (1, -1)] as [(Float, Float)] {
                g += [gx + x * radius, gy, gz + z * radius, 0, 1, 0, 1, 1, 1, 0, 0]
            }
            // The axes: arrows from the south-west corner, 10 m out, half the
            // model's longer side long, 30 m at least.
            let o = SIMD3<Float>(Float(lo.x) - 10, Float(lo.y), Float(hi.z) + 10)
            let len = Float(max(30, max(hi.x - lo.x, hi.z - lo.z) / 2))
            var a: [Float] = []
            var counts: [Int] = []
            for d in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, -1), SIMD3<Float>(0, 1, 0)] {
                let before = a.count
                arrow(&a, from: o, along: d, length: len)
                counts.append((a.count - before) / 11)
            }
            let labels: [(String, SIMD3<Float>)] = [("X  E", o + SIMD3(len + 3, 0, 0)), ("Y  N", o + SIMD3(0, 0, -len - 3)), ("Z", o + SIMD3(0, len + 3, 0))]
            return LitModel(vertices: buffer, count: v.count / 11, ground: device.makeBuffer(bytes: g, length: g.count * 4)!,
                            axes: device.makeBuffer(bytes: a, length: a.count * 4)!, axisCounts: counts, labels: labels, corners: corners,
                            centre: centre, size: hi - lo, triangles: r.triangles)
        }

        /// An arrow: a bar 0.5 m across and a cone 4 m long, 1.4 m across,
        /// as triangles in the lit layout (11 floats a vertex).
        static func arrow(_ a: inout [Float], from o: SIMD3<Float>, along d: SIMD3<Float>, length: Float) {
            let helper: SIMD3<Float> = abs(d.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let u = simd_normalize(simd_cross(d, helper)), w = simd_cross(d, u)
            func put(_ p: SIMD3<Float>) { a += [p.x, p.y, p.z, 0, 1, 0, 1, 1, 1, 0, 0] }
            func tri(_ p: SIMD3<Float>, _ q: SIMD3<Float>, _ r: SIMD3<Float>) { put(p); put(q); put(r) }
            // Thin for their length: a bar 0.5 m across and a cone 1.6 m
            // across, 5 m long, whatever the length.
            let n = 12, barR: Float = 0.25, coneR: Float = 0.8, coneLen: Float = 5
            let neck = o + d * (length - coneLen), tip = o + d * length
            func ring(_ c: SIMD3<Float>, _ r: Float, _ k: Int) -> SIMD3<Float> {
                let t = 2 * Float.pi * Float(k) / Float(n)
                return c + u * (r * cos(t)) + w * (r * sin(t))
            }
            for k in 0..<n {
                let k1 = (k + 1) % n
                tri(ring(o, barR, k), ring(o, barR, k1), ring(neck, barR, k1))
                tri(ring(o, barR, k), ring(neck, barR, k1), ring(neck, barR, k))
                tri(o, ring(o, barR, k1), ring(o, barR, k))
                tri(ring(neck, coneR, k), ring(neck, coneR, k1), tip)
                tri(neck, ring(neck, coneR, k1), ring(neck, coneR, k))
            }
        }

        /// As a plain model's record (its size, its count), for the view's
        /// status and framing.
        func plain(_ note: String) -> Model {
            Model(parts: [], ground: ground, centre: centre, size: size, triangles: triangles, lit: self, note: note)
        }
    }

    /// A model on the GPU: one buffer of vertices per part, with its texture.
    struct Model {
        struct Part { let vertices: MTLBuffer; let count: Int; let texture: MTLTexture?; let colour: SIMD4<Float> }
        let parts: [Part]
        let ground: MTLBuffer
        let centre: SIMD3<Double>
        let size: SIMD3<Double>
        let triangles: Int
        /// The same model for the previews' light, when it is shown lit.
        var lit: LitModel? = nil
        var note = ""

        static func load(_ url: URL, device: MTLDevice) throws -> Model {
            try load([LandmarkView.Placed(url: url, origin: .zero)], device: device)
        }

        /// Several models as one, each moved to its origin (east, north, up).
        static func load(_ placed: [LandmarkView.Placed], device: MTLDevice) throws -> Model {
            let loader = MTKTextureLoader(device: device)
            var lo = SIMD3<Double>(repeating: .infinity), hi = -lo
            var parts: [Part] = []
            var triangles = 0
            for p in placed {
                let o = p.origin
                for part in try GLTF.primitives(p.url) {
                    // The build's +Z up (east, north, up) back to the view's +Y up,
                    // -Z north, as the tiles are drawn.
                    let tris = part.tris.map { SIMD3($0.x + o.x, $0.z + o.z, -($0.y + o.y)) }
                    var v: [Float] = []
                    v.reserveCapacity(tris.count * 8)
                    for t in stride(from: 0, to: tris.count - 2, by: 3) {
                        let a = tris[t], b = tris[t + 1], c = tris[t + 2]
                        let n = simd_normalize(simd_cross(b - a, c - a))
                        for k in 0..<3 {
                            let p = tris[t + k]
                            lo = simd_min(lo, p)
                            hi = simd_max(hi, p)
                            let uv = part.uvs?[t + k] ?? .zero
                            v += [Float(p.x), Float(p.y), Float(p.z), Float(n.x), Float(n.y), Float(n.z), Float(uv.x), Float(uv.y)]
                        }
                    }
                    guard !v.isEmpty, let buffer = device.makeBuffer(bytes: v, length: v.count * 4) else { continue }
                    let texture = part.material.image.flatMap {
                        try? loader.newTexture(data: $0, options: [.SRGB: false, .generateMipmaps: true,
                                                                   .textureUsage: MTLTextureUsage.shaderRead.rawValue])
                    }
                    let f = part.material.factor.map(Float.init) + [1, 1, 1, 1]
                    parts.append(Part(vertices: buffer, count: v.count / 8, texture: texture, colour: SIMD4(f[0], f[1], f[2], 1)))
                    triangles += v.count / 24
                }
            }
            return try make(parts: parts, lo: lo, hi: hi, triangles: triangles, device: device)
        }

        /// Boxes extruded from outlines, as a map of OSM data shows
        /// buildings: walls light, roofs a little darker.
        static func extruded(_ boxes: [TileLandmark.Box], device: MTLDevice) throws -> Model {
            var walls: [Float] = [], roofs: [Float] = []
            var lo = SIMD3<Double>(repeating: .infinity), hi = -lo
            // East, up, south: the view's axes.
            func add(_ v: inout [Float], _ p: SIMD3<Double>, _ n: SIMD3<Double>) {
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
                v += [Float(p.x), Float(p.y), Float(p.z), Float(n.x), Float(n.y), Float(n.z), 0, 0]
            }
            func at(_ q: Vec2, _ h: Double) -> SIMD3<Double> { SIMD3(q.x, h, -q.y) }
            for box in boxes {
                for rings in box.polygons where !rings.isEmpty && rings[0].count >= 3 {
                    for ring in rings {
                        for i in ring.indices {
                            let a = ring[i], b = ring[(i + 1) % ring.count]
                            let d = b - a
                            guard simd_length(d) > 1e-6 else { continue }
                            let n = simd_normalize(SIMD3(d.y, 0, d.x))
                            let (a0, b0, a1, b1) = (at(a, box.base), at(b, box.base), at(a, box.top), at(b, box.top))
                            for p in [a0, b0, b1, a0, b1, a1] { add(&walls, p, n) }
                        }
                    }
                    let shape = Geometry.polygon(rings[0].map { P2($0.x, $0.y) }, holes: rings.dropFirst().map { $0.map { P2($0.x, $0.y) } })
                    for t in shape.constrainedDelaunay() where t.count == 3 {
                        for p in t { add(&roofs, at(Vec2(p.x, p.y), box.top), SIMD3(0, 1, 0)) }
                    }
                }
            }
            var parts: [Part] = []
            for (v, colour) in [(walls, SIMD4<Float>(0.86, 0.84, 0.80, 1)), (roofs, SIMD4<Float>(0.66, 0.66, 0.70, 1))] where !v.isEmpty {
                parts.append(Part(vertices: device.makeBuffer(bytes: v, length: v.count * 4)!, count: v.count / 8,
                                  texture: nil, colour: colour))
            }
            return try make(parts: parts, lo: lo, hi: hi, triangles: (walls.count + roofs.count) / 24, device: device)
        }

        /// The model of its parts, over a ground plane under its foot.
        private static func make(parts: [Part], lo: SIMD3<Double>, hi: SIMD3<Double>, triangles: Int,
                                 device: MTLDevice) throws -> Model {
            guard !parts.isEmpty else { throw TileModel.Failure.glb("no triangles") }
            // The ground: a square under the model, a little below its foot.
            let c = (lo + hi) / 2, r = Float(max(hi.x - lo.x, hi.z - lo.z) * 1.5 + 40)
            let (gx, gy, gz) = (Float(c.x), Float(lo.y) - 0.02, Float(c.z))
            let g: [Float] = [
                gx - r, gy, gz - r, 0, 1, 0, 0, 0, gx - r, gy, gz + r, 0, 1, 0, 0, 0, gx + r, gy, gz + r, 0, 1, 0, 0, 0,
                gx - r, gy, gz - r, 0, 1, 0, 0, 0, gx + r, gy, gz + r, 0, 1, 0, 0, 0, gx + r, gy, gz - r, 0, 1, 0, 0, 0,
            ]
            return Model(parts: parts, ground: device.makeBuffer(bytes: g, length: g.count * 4)!,
                         centre: c, size: hi - lo, triangles: triangles)
        }
    }
}
