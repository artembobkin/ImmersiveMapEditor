import Foundation
import Geometry
import GLTF

/// A model's faces in the tile's metres, and the colour covering each in
/// its atlas.
extension Imported {
    // MARK: Reading a model

    /// The faces of one model in the tile's metres, with their atlas UVs, and
    /// the atlases.
    static func readModel(_ place: Placement, _ tile: Tile) throws -> ([Face], [String: GLTF.Image]) {
        let (triangles, images) = try GLTF.read(place.glb)
        let scale = cos(tile.centreLatitude * .pi / 180) / cos(place.latitude * .pi / 180)
        // A model stands on the ground plane.
        let offset = V3(place.origin.x, place.origin.y, place.altitude + Level.ground)
        var faces: [Face] = []
        for t in triangles {
            let f = Face()
            f.corners = t.corners.map { $0 * scale + offset }
            f.image = t.image
            f.material = t.material
            f.uvs = t.uvs
            f.colour = f.image != nil ? mainColour(f, images) : t.base
            let n = (f.corners[1] - f.corners[0]).cross(f.corners[2] - f.corners[0])
            f.normal = n.length > 1e-12 ? n.normalized : n
            f.area = n.length / 2
            faces.append(f)
        }
        return (faces, images)
    }

    static func pixel(_ images: [String: GLTF.Image], _ name: String, _ u: Double, _ v: Double) -> SIMD3<Float> {
        let px = images[name]!
        let fu = u - floor(u), fv = v - floor(v)
        return px.rgb(Int(fv * Double(px.height)) % px.height, Int(fu * Double(px.width)) % px.width)
    }

    /// The colour covering most of a face in its atlas: the corners pulled to
    /// the middle, and the middle, voted.
    static func mainColour(_ f: Face, _ images: [String: GLTF.Image]) -> (Int, Int, Int) {
        let uvs = f.uvs!
        let mid = uvs.reduce(P2.zero, +) / Double(uvs.count)
        var samples = [mid]
        for t in [0.35, 0.7] { for uv in uvs { samples.append(mid + (uv - mid) * t) } }
        var keys: [[Int]] = []
        for s in samples {
            let c = pixel(images, f.image!, s.x, s.y)
            keys.append([c.x, c.y, c.z].map { Int(($0 * 255).rounded(.toNearestOrEven)) / 12 * 12 + 6 })
        }
        // A tie goes where the Python build sent it: the first in the order
        // a CPython set of the keys iterates.
        var best = keys[0], most = 0
        for k in pythonSetOrder(keys) {
            let n = keys.filter { $0 == k }.count
            if n > most { best = k; most = n }
        }
        return (min(255, best[0]), min(255, best[1]), min(255, best[2]))
    }

    /// CPython's hash of a tuple of small non-negative ints (xxHash based,
    /// Objects/tupleobject.c).
    static func pythonHash(_ t: [Int]) -> UInt64 {
        let p1: UInt64 = 11_400_714_785_074_694_791, p2: UInt64 = 14_029_467_366_897_019_727
        let p5: UInt64 = 2_870_177_450_012_600_261
        var acc = p5
        for v in t {
            acc &+= UInt64(v) &* p2
            acc = (acc << 31) | (acc >> 33)
            acc &*= p1
        }
        acc &+= UInt64(t.count) ^ (p5 ^ 3_527_539)
        return acc == UInt64.max ? 1_546_275_796 : acc
    }

    /// The distinct keys in the order `set(keys)` iterates them in CPython:
    /// open addressing, nine linear probes, then perturbation, the table
    /// growing from 8 slots to four times its use when three fifths full
    /// (Objects/setobject.c).
    static func pythonSetOrder(_ keys: [[Int]]) -> [[Int]] {
        var table: [[Int]?] = Array(repeating: nil, count: 8)
        var used = 0
        func insert(_ k: [Int], into t: inout [[Int]?]) -> Bool {
            let mask = t.count - 1
            let hash = pythonHash(k)
            var perturb = hash
            var i = Int(hash & UInt64(mask))
            while true {
                var probes = i + 9 <= mask ? 9 : 0
                var j = i
                while true {
                    if t[j] == nil { t[j] = k; return true }
                    if t[j]! == k { return false }
                    if probes == 0 { break }
                    probes -= 1
                    j += 1
                }
                perturb >>= 5
                i = Int((UInt64(i) &* 5 &+ 1 &+ perturb) & UInt64(mask))
            }
        }
        for k in keys where insert(k, into: &table) {
            used += 1
            if used * 5 >= (table.count - 1) * 3 {
                var size = 8
                while size <= used * 4 { size <<= 1 }
                var grown: [[Int]?] = Array(repeating: nil, count: size)
                for case let old? in table { _ = insert(old, into: &grown) }
                table = grown
            }
        }
        return table.compactMap { $0 }
    }
}
