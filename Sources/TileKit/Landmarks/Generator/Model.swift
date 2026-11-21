import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

extension LandmarkGenerator {
    // MARK: The model

    public final class Model {
        /// The caricature's sizes, by their short name in the extensions of the
        /// model's other files, as when the model was declared in one file
        /// with the generator.
        typealias Caricature = LandmarkGenerator.Caricature

        /// Triangles by colour name, three corners each, X east, Y north, Z up.
        var tris: [String: [V3]] = [:]
        /// How many sides a round solid gets (a tube, a ball) unless told:
        /// more for a sculpture drawn larger than life, whose size shows
        /// the detail (the user, 2026-11-04).
        var roundSegments = 10
        /// Every triangle in the order it was made, with its colour and the
        /// closed solid it belongs to: what `separate` and `unite` work on.
        var faces: [(a: V3, b: V3, c: V3, colour: String, solid: Int)] = []
        /// The solid the faces made now belong to: every builder of a closed
        /// body begins one.
        var solid = 0
        func begin() { solid += 1 }
        /// How the union went: solids united, solids kept as they were.
        public private(set) var united = 0
        public private(set) var keptRaw = 0
        /// Triangles no outside camera could see, dropped (VisiblePass).
        public private(set) var hidden = 0

        /// Drops the triangles no camera around or above the model sees.
        func cullHidden() {
            let colours = tris.keys.sorted()
            var flat: [V3] = []
            var owner: [(String, Int)] = []
            for c in colours {
                let list = tris[c]!
                flat += list
                for t in stride(from: 0, to: list.count, by: 3) { owner.append((c, t)) }
            }
            guard !flat.isEmpty, let seen = VisiblePass.visible(flat) else { return }
            var out: [String: [V3]] = [:]
            for (k, (c, _)) in owner.enumerated() where seen[k] {
                out[c, default: []] += [flat[3 * k], flat[3 * k + 1], flat[3 * k + 2]]
            }
            hidden = owner.count - seen.filter { $0 }.count
            if ProcessInfo.processInfo.environment["LANDMARK_UNION_DEBUG"] != nil {
                var dropped: [String: Int] = [:]
                var shown = 0
                for (k, (c, _)) in owner.enumerated() where !seen[k] {
                    dropped[c, default: 0] += 1
                    if c == "rim", shown < 6 {
                        shown += 1
                        let (a, b, cc) = (flat[3 * k], flat[3 * k + 1], flat[3 * k + 2])
                        let n = simd_cross(b - a, cc - a)
                        FileHandle.standardError.write(Data(String(format: "  hidden rim: centre (%.1f, %.1f, %.1f), normal (%.2f, %.2f, %.2f), area %.3f\n",
                            (a.x + b.x + cc.x) / 3, (a.y + b.y + cc.y) / 3, (a.z + b.z + cc.z) / 3, n.x / simd_length(n), n.y / simd_length(n), n.z / simd_length(n), simd_length(n) / 2).utf8))
                    }
                }
                FileHandle.standardError.write(Data("hidden by colour: \(dropped.sorted { $0.value > $1.value })\n".utf8))
            }
            if ProcessInfo.processInfo.environment["LANDMARK_NO_CULL"] != nil { return }
            tris = out
        }

        public var triangles: Int { tris.values.reduce(0) { $0 + $1.count } / 3 }

        /// Two faces on one plane, one over the other, fight for the
        /// pixels (a landing's top on a stylobate's, a box flush with a
        /// wall): the one made later (the detail, not the wall) moves 2 cm
        /// out along its normal. Called once the model is whole.
        func separate() {
            // A face's own normal, and the plane's (the same for a face
            // looking the other way: a box's bottom on a mass's top).
            struct Face { let i: Int; let n: V3; let d: Double; let lo: V3; let hi: V3 }
            var planes: [String: [Face]] = [:]
            for (i, f) in faces.enumerated() {
                var n = simd_cross(f.b - f.a, f.c - f.a)
                let len = simd_length(n)
                guard len > 1e-9 else { continue }
                n /= len
                var plane = n
                if plane.z < -1e-6 || (abs(plane.z) <= 1e-6 && (plane.y < -1e-6 || (abs(plane.y) <= 1e-6 && plane.x < 0))) { plane = -plane }
                let key = String(format: "%.2f,%.2f,%.2f", plane.x, plane.y, plane.z)
                planes[key, default: []].append(Face(i: i, n: n, d: simd_dot(plane, f.a), lo: simd_min(simd_min(f.a, f.b), f.c), hi: simd_max(simd_max(f.a, f.b), f.c)))
            }
            var moved = Set<Int>()
            for group in planes.values where group.count > 1 {
                let sorted = group.sorted { $0.d < $1.d }
                for k in 0..<sorted.count {
                    let f = sorted[k]
                    guard !moved.contains(f.i) else { continue }
                    var j = k + 1
                    while j < sorted.count, sorted[j].d - f.d < 0.02 {
                        let g = sorted[j]
                        j += 1
                        guard !moved.contains(g.i), f.i != g.i,
                              f.lo.x < g.hi.x + 0.01, g.lo.x < f.hi.x + 0.01, f.lo.y < g.hi.y + 0.01, g.lo.y < f.hi.y + 0.01,
                              f.lo.z < g.hi.z + 0.01, g.lo.z < f.hi.z + 0.01 else { continue }
                        let later = max(f.i, g.i)
                        let t = faces[later]
                        var nn = simd_cross(t.b - t.a, t.c - t.a)
                        nn /= max(simd_length(nn), 1e-9)
                        let push = nn * 0.02
                        faces[later].a += push
                        faces[later].b += push
                        faces[later].c += push
                        moved.insert(later)
                    }
                }
            }
            guard !moved.isEmpty else { return }
            tris = [:]
            for f in faces { tris[f.colour, default: []] += [f.a, f.b, f.c] }
        }

        public var summary: String {
            let all = tris.values.flatMap { $0 }
            guard let first = all.first else { return "nothing built" }
            let lo = all.reduce(first) { simd_min($0, $1) }, hi = all.reduce(first) { simd_max($0, $1) }
            return String(format: "%d triangles (%d solids united into one shell%@%@), %.0f × %.0f m, %.1f m high, colours %@", triangles,
                          united, keptRaw > 0 ? ", \(keptRaw) kept apart, not closed" : "", hidden > 0 ? ", \(hidden) hidden dropped" : "",
                          hi.x - lo.x, hi.y - lo.y, hi.z, tris.keys.sorted().joined(separator: " "))
        }

        public func write(_ url: URL, name: String) throws {
            let parts = tris.keys.sorted().map { c -> GLTF.Part in
                let (r, g, b) = Palette.rgb(Palette.hex(c) ?? "#FF00FF")
                return GLTF.Part(material: .init(name: c, factor: [Double(r) / 255, Double(g) / 255, Double(b) / 255, 1]),
                                 tris: tris[c]!, uvs: nil)
            }
            try GLTF.writeModel(url, parts, name: name)
        }

        /// The solids united into one shell by Manifold: the faces grouped
        /// by solid, each welded into a mesh, the union's triangles coloured
        /// by the face they came from. A solid Manifold will not take (not
        /// closed, a face turned in) stays as it was, apart. Downward faces
        /// on the ground go: nothing sees them.
        @discardableResult
        func unite() -> Bool {
            var bySolid: [Int: [Int]] = [:]
            for (i, f) in faces.enumerated() { bySolid[f.solid, default: []].append(i) }
            let ids = bySolid.keys.sorted()
            // A face id a planar face of one colour in one solid, so the
            // union's simplification can merge the triangles of a face again.
            var groupOf: [String: Int] = [:]
            var groupColour: [String] = []
            func group(_ i: Int) -> UInt32 {
                let f = faces[i]
                var n = simd_cross(f.b - f.a, f.c - f.a)
                n /= max(simd_length(n), 1e-12)
                let key = String(format: "%d|%@|%.3f,%.3f,%.3f|%.3f", f.solid, f.colour, n.x, n.y, n.z, simd_dot(n, f.a))
                if let g = groupOf[key] { return UInt32(g) }
                groupOf[key] = groupColour.count
                groupColour.append(f.colour)
                return UInt32(groupColour.count - 1)
            }
            var meshes: [SolidUnion.Mesh] = []
            for id in ids {
                var index: [SIMD3<Int64>: UInt32] = [:]
                var mesh = SolidUnion.Mesh(verts: [], tris: [], faceIDs: [])
                func vertex(_ p: V3) -> UInt32 {
                    let key = SIMD3<Int64>(Int64((p.x * 10_000).rounded()), Int64((p.y * 10_000).rounded()), Int64((p.z * 10_000).rounded()))
                    if let k = index[key] { return k }
                    let k = UInt32(mesh.verts.count / 3)
                    index[key] = k
                    mesh.verts += [Float(Double(key.x) / 10_000), Float(Double(key.y) / 10_000), Float(Double(key.z) / 10_000)]
                    return k
                }
                for i in bySolid[id]! {
                    let f = faces[i]
                    let (a, b, c) = (vertex(f.a), vertex(f.b), vertex(f.c))
                    guard a != b, b != c, a != c else { continue }
                    mesh.tris += [a, b, c]
                    mesh.faceIDs.append(group(i))
                }
                meshes.append(mesh)
            }
            var statuses: [Int32] = []
            let result = SolidUnion.unite(meshes, statuses: &statuses)
            if ProcessInfo.processInfo.environment["LANDMARK_UNION_DEBUG"] != nil {
                var counts: [Int32: Int] = [:]
                for s in statuses { counts[s, default: 0] += 1 }
                // How many shells the union has: the triangles' vertex connectivity.
                var shells = 0
                if let result {
                    var parent = Array(0..<(result.verts.count / 3))
                    func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
                    for t in stride(from: 0, to: result.tris.count, by: 3) {
                        let a = find(Int(result.tris[t])), b = find(Int(result.tris[t + 1])), c = find(Int(result.tris[t + 2]))
                        parent[b] = a; parent[find(c)] = find(a)
                    }
                    var used = Set<Int>()
                    var size: [Int: Int] = [:], lo: [Int: V3] = [:], hi: [Int: V3] = [:]
                    for t in stride(from: 0, to: result.tris.count, by: 3) {
                        let root = find(Int(result.tris[t]))
                        used.insert(root)
                        size[root, default: 0] += 1
                        for k in 0..<3 {
                            let i = Int(result.tris[t + k]) * 3
                            let p = V3(Double(result.verts[i]), Double(result.verts[i + 1]), Double(result.verts[i + 2]))
                            lo[root] = simd_min(lo[root] ?? p, p)
                            hi[root] = simd_max(hi[root] ?? p, p)
                        }
                    }
                    shells = used.count
                    for (root, n) in size.sorted(by: { $0.value > $1.value }).prefix(12) {
                        let a = lo[root]!, b = hi[root]!
                        FileHandle.standardError.write(Data(String(format: "  shell: %d tris, x %.0f..%.0f y %.0f..%.0f z %.1f..%.1f\n", n, a.x, b.x, a.y, b.y, a.z, b.z).utf8))
                    }
                }
                FileHandle.standardError.write(Data("union: \(meshes.count) solids, statuses \(counts.sorted { $0.key < $1.key }), result \(result == nil ? "none" : "\(result!.faceIDs.count) triangles in \(shells) shells")\n".utf8))
                var reported = 0
                for (k, s) in statuses.enumerated() where s != 0 && reported < 12 {
                    reported += 1
                    let m = meshes[k]
                    // The halfedges: a closed, consistently wound mesh has every
                    // directed edge once and its opposite once.
                    var edges: [String: Int] = [:]
                    for t in stride(from: 0, to: m.tris.count, by: 3) {
                        for e in 0..<3 { edges["\(m.tris[t + e])>\(m.tris[t + (e + 1) % 3])", default: 0] += 1 }
                    }
                    var open = 0, doubled = 0
                    var samples: [String] = []
                    for (e, n) in edges {
                        let parts = e.split(separator: ">").map { Int($0)! }
                        let back = edges["\(parts[1])>\(parts[0])"] ?? 0
                        if n > 1 { doubled += 1 }
                        if back == 0 {
                            open += 1
                            if samples.count < 3 {
                                let p = Array(m.verts[(parts[0] * 3)..<(parts[0] * 3 + 3)]), q = Array(m.verts[(parts[1] * 3)..<(parts[1] * 3 + 3)])
                                samples.append(String(format: "(%.2f, %.2f, %.2f)-(%.2f, %.2f, %.2f)", p[0], p[1], p[2], q[0], q[1], q[2]))
                            }
                        }
                    }
                    FileHandle.standardError.write(Data("  solid \(ids[k]): status \(s), \(m.verts.count / 3) verts, \(m.tris.count / 3) tris, \(open) open halfedges, \(doubled) doubled, colours \(Set(bySolid[ids[k]]!.map { faces[$0].colour }).sorted()) e.g. \(samples.joined(separator: " "))\n".utf8))
                    if ProcessInfo.processInfo.environment["LANDMARK_UNION_DUMP"] == "\(ids[k])" {
                        for i in bySolid[ids[k]]! {
                            let f = faces[i]
                            FileHandle.standardError.write(Data(String(format: "    %@ (%.2f,%.2f,%.2f) (%.2f,%.2f,%.2f) (%.2f,%.2f,%.2f)\n", f.colour, f.a.x, f.a.y, f.a.z, f.b.x, f.b.y, f.b.z, f.c.x, f.c.y, f.c.z).utf8))
                        }
                    }
                }
            }
            guard let result else { return false }
            var out: [String: [V3]] = [:]
            for t in 0..<(result.faceIDs.count) {
                let id = Int(result.faceIDs[t])
                guard id < groupColour.count else { continue }
                func v(_ k: Int) -> V3 {
                    let i = Int(result.tris[3 * t + k]) * 3
                    return V3(Double(result.verts[i]), Double(result.verts[i + 1]), Double(result.verts[i + 2]))
                }
                let (a, b, c) = (v(0), v(1), v(2))
                let n = simd_cross(b - a, c - a)
                if n.z < 0, max(a.z, b.z, c.z) < 0.005 { continue }
                out[groupColour[id], default: []] += [a, b, c]
            }
            // The solids not taken, as they were.
            for (k, id) in ids.enumerated() where statuses[k] != 0 {
                for i in bySolid[id]! { out[faces[i].colour, default: []] += [faces[i].a, faces[i].b, faces[i].c] }
            }
            tris = out
            united = statuses.filter { $0 == 0 }.count
            keptRaw = statuses.count - united
            if let path = ProcessInfo.processInfo.environment["LANDMARK_UNION_OBJ"] {
                var obj = ""
                var n = 0
                for (colour, list) in out {
                    obj += "g \(colour)\n"
                    for p in list { obj += String(format: "v %.4f %.4f %.4f\n", p.x, p.y, p.z) }
                    for t in stride(from: 0, to: list.count, by: 3) { obj += "f \(n + t + 1) \(n + t + 2) \(n + t + 3)\n" }
                    n += list.count
                }
                try? obj.write(toFile: path, atomically: true, encoding: .utf8)
            }
            return true
        }
    }
}
