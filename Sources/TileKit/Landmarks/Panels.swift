import Foundation
import Geometry
import GLTF

/// Faces grouped into panels, and the palette's landmark colour of each.
extension Imported {
    // MARK: Panels and colours

    struct EdgeKey: Hashable {
        let a: SIMD3<Int64>, b: SIMD3<Int64>
    }

    /// Faces grouped by shared edges (by position: an importer splits
    /// vertices at UV seams) whose normals are closer than `limit` (a
    /// cosine), and on one plane if asked. Returns a group index per face.
    static func groups(_ faces: [Face], _ limit: Double, samePlane: Bool = false) -> [Int] {
        var parent = Array(faces.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        // Millimetres, rounded as Python's round(v, 3) rounds: the exact
        // binary value, so a value near a half rounds the way its digits say.
        func mm(_ v: Double) -> Int64 {
            let s = v * 1000, r = s.rounded(.toNearestOrEven)
            if abs(abs(s - r) - 0.5) > 1e-6 { return Int64(r) }
            return Int64((Double(String(format: "%.3f", v))! * 1000).rounded())
        }
        func key(_ c: V3) -> SIMD3<Int64> { SIMD3(mm(c.x), mm(c.y), mm(c.z)) }
        func less(_ a: SIMD3<Int64>, _ b: SIMD3<Int64>) -> Bool {
            a.x != b.x ? a.x < b.x : a.y != b.y ? a.y < b.y : a.z < b.z
        }
        var byEdge: [EdgeKey: [Int]] = [:]
        var order: [EdgeKey] = []
        for (i, f) in faces.enumerated() {
            let keys = f.corners.map(key)
            for k in keys.indices {
                let a = keys[k], b = keys[(k + 1) % keys.count]
                let e = less(b, a) ? EdgeKey(a: b, b: a) : EdgeKey(a: a, b: b)
                if byEdge[e] == nil { order.append(e) }
                byEdge[e, default: []].append(i)
            }
        }
        for e in order {
            let shared = byEdge[e]!
            let i = shared[0]
            for j in shared.dropFirst() {
                let fi = faces[i], fj = faces[j]
                if fi.normal.dot(fj.normal) <= limit { continue }
                if samePlane && abs((fj.corners[0] - fi.corners[0]).dot(fi.normal)) > 0.02 { continue }
                parent[find(j)] = find(i)
            }
        }
        return faces.indices.map(find)
    }

    /// The landmark colour nearest to an atlas colour, or glass.
    static func family(_ colour: (Int, Int, Int)) -> String {
        var best = "", bestD = Int.max
        let choices = Palette.landmark.map { (Palette.rgb($0.1), $0.0) } + glass.map { ($0, "lm_glass") }
        for (c, name) in choices {
            // Weighted for the eye: green counts most, blue least.
            let d = 2 * (c.0 - colour.0) * (c.0 - colour.0) + 4 * (c.1 - colour.1) * (c.1 - colour.1)
                + 3 * (c.2 - colour.2) * (c.2 - colour.2)
            if d < bestD { best = name; bestD = d }
        }
        return best
    }
}
