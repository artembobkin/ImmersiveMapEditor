import Foundation
import Geometry

/// How the tile's edge treats a face: cut along it; a building this tile
/// owns, kept whole; a building a neighbour owns, there for the light map
/// only.
public enum Owner: Int8 { case cut = 0, whole = 1, foreign = 2 }

/// Triangles: corners (9 doubles each), palette UVs (6 each, V up), how the
/// tile's edge treats them, and the height their wall shades over (2 each,
/// equal when there is none).
public struct Triangles {
    public var pos: [Double] = []
    public var uv: [Double] = []
    public var owner: [Owner] = []
    public var wall: [Double] = []
    public var count: Int { owner.count }

    public init() {}

    public func corner(_ t: Int, _ i: Int) -> V3 { V3(pos[t * 9 + i * 3], pos[t * 9 + i * 3 + 1], pos[t * 9 + i * 3 + 2]) }

    public func normal(_ t: Int) -> V3 {
        let a = corner(t, 0)
        return (corner(t, 1) - a).cross(corner(t, 2) - a)
    }

    mutating func append(_ p: [V3], _ uvs: [P2], _ o: Owner, _ w: (Double, Double)) {
        for v in p { pos += [v.x, v.y, v.z] }
        for u in uvs { uv += [u.x, u.y] }
        owner.append(o)
        wall += [w.0, w.1]
    }

    func filtered(_ keep: (Int) -> Bool) -> Triangles {
        var out = Triangles()
        for t in 0..<count where keep(t) {
            out.pos += pos[(t * 9)..<(t * 9 + 9)]
            out.uv += uv[(t * 6)..<(t * 6 + 6)]
            out.owner.append(owner[t])
            out.wall += wall[(t * 2)..<(t * 2 + 2)]
        }
        return out
    }
}
