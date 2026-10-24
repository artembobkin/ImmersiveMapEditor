import Foundation
import Geometry
import GLTF

/// A flat wall rebuilt with its windows as recesses.
extension Imported {
    /// A flat wall rebuilt with its windows as recesses: the wall with holes,
    /// each window's four reveals and its glass at `windowDepth`.
    static func buildWall(_ b: Builder, _ wall: Wall, _ family: String, _ glass: String?, _ kind: String) -> Int {
        func at(_ u: Double, _ v: Double, _ depth: Double = 0) -> V3 {
            wall.origin + wall.along * u + wall.up * v - wall.n * depth
        }
        var made = 0
        for part in wall.outline.difference(.unaryUnion(wall.rects)).polygons {
            for tri in part.constrainedDelaunay() where tri.count == 3 {
                var p = tri.map { at($0.x, $0.y) }
                if (p[1] - p[0]).cross(p[2] - p[0]).dot(wall.n) < 0 { p = [p[0], p[2], p[1]] }
                if b.sided(p, family, kind) > 0 { made += 1 }
            }
        }
        let d = windowDepth
        for r in wall.rects {
            let (u0, v0, u1, v1) = r.bounds
            // Reveals face into the opening: bottom up, top down, sides inward.
            let quads: [((Double, Double), (Double, Double), V3)] = [
                ((u0, v0), (u1, v0), wall.up), ((u1, v1), (u0, v1), -wall.up),
                ((u1, v0), (u1, v1), -wall.along), ((u0, v1), (u0, v0), wall.along),
            ]
            for ((ua, va), (ub, vb), facing) in quads {
                var p = [at(ua, va), at(ub, vb), at(ub, vb, d), at(ua, va, d)]
                if (p[1] - p[0]).cross(p[2] - p[0]).dot(facing) < 0 { p = [p[0], p[3], p[2], p[1]] }
                b.sided(p, family + ".reveal", kind)
            }
            var p = [at(u0, v0, d), at(u1, v0, d), at(u1, v1, d), at(u0, v1, d)]
            if (p[1] - p[0]).cross(p[2] - p[0]).dot(wall.n) < 0 { p.reverse() }
            if let glass {
                b.flat(p, glass, kind)
            } else {
                b.sided(p, family + ".glass", kind)
            }
            made += 6
        }
        return made
    }
}
