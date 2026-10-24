import Foundation
import Geometry
import simd

/// The tile's one mesh while it is being built: triangles, each made with
/// its winding set and its palette UV (TEXCOORD_0) on each corner. Normals
/// are never recalculated, so every helper winds its faces to face outward.
/// A face of more than three corners is cut into triangles as it is made (a
/// fan if it is convex, ear clipping if not).
public final class Builder {
    public var tris = Triangles()
    /// The height a wall face shades over in the light map: the whole wall it
    /// is part of, not the face alone (see Lighting.lightUVs).
    public var span: (Double, Double)?
    /// How the tile's edge treats the faces made now.
    public var whole: Owner = .cut
    public let palette: PaletteTexture
    public var counts: [String: Int] = [:]

    public init(palette: PaletteTexture) { self.palette = palette }

    /// A face of three or more corners, wound as given. Returns how many
    /// triangles it made.
    @discardableResult
    public func face(_ points: [V3], _ uvs: [P2], _ kind: String) -> Int {
        var made = 0
        for (i, j, k) in triangulate(points) {
            let a = points[i], b = points[j], c = points[k]
            let n = (b - a).cross(c - a)
            if simd_length_squared(n) < 1e-14 { continue }
            tris.append([a, b, c], [uvs[i], uvs[j], uvs[k]], whole, span ?? (0, 0))
            made += 1
        }
        counts[kind, default: 0] += made
        return made
    }

    @discardableResult
    public func flat(_ points: [V3], _ colour: String, _ kind: String) -> Int {
        // A family with sides, seen from above.
        let name = palette.has(colour) ? colour : colour + ".lit"
        let uv = palette.uv(name)
        return face(points, Array(repeating: uv, count: points.count), kind)
    }

    /// A face coloured by the side of the sun it looks to: `family` is a wall
    /// or "roof", the palette holds its `.lit`, `.side` and `.shade`. A face
    /// looking straight up takes the lit shade.
    @discardableResult
    public func sided(_ points: [V3], _ family: String, _ kind: String) -> Int {
        let n = (points[1] - points[0]).cross(points[2] - points[0])
        let side = abs(n.z) < 0.97 * n.length ? Palette.side(n.x, n.y) : "lit"
        return flat(points, "\(family).\(side)", kind)
    }

    /// A face by `sided` if its colour has sides, plain otherwise.
    @discardableResult
    public func paint(_ points: [V3], _ colour: String, _ kind: String) -> Int {
        palette.has("\(colour).lit") ? sided(points, colour, kind) : flat(points, colour, kind)
    }

    /// A horizontal polygon with its holes, facing up (or down). With
    /// `uvOf`, each corner takes its own UV instead of the colour's cell.
    public func fill(_ poly: Geometry, _ z: Double, _ colour: String, _ kind: String, down: Bool = false,
                     uvOf: ((Double, Double) -> P2)? = nil) {
        let valid = poly.isValid ? poly : poly.buffer(0)
        for part in valid.polygons {
            for tri in part.constrainedDelaunay() where tri.count == 3 {
                var p = tri.map { v3($0, z) }
                let n = (p[1] - p[0]).cross(p[2] - p[0])
                if n.length < 1e-6 { continue }
                if (n.z < 0) != down { p = [p[0], p[2], p[1]] }
                if let uvOf {
                    face(p, p.map { uvOf($0.x, $0.y) }, kind)
                } else {
                    flat(p, colour, kind)
                }
            }
        }
    }

    /// The faces of a template (`cone`) moved by `transform`, each coloured
    /// by `colourOf(normal)`, a palette name. A face `drop` is true for is
    /// left out.
    public func instance(_ faces: [[V3]], _ transform: (V3) -> V3, _ colourOf: (V3) -> String, _ kind: String,
                         drop: (([V3]) -> Bool)? = nil) {
        for points in faces {
            let p = points.map(transform)
            if let drop, drop(p) { continue }
            let n = (p[1] - p[0]).cross(p[2] - p[0])
            if n.length < 1e-9 { continue }
            let uv = palette.uv(colourOf(n.normalized))
            face(p, Array(repeating: uv, count: p.count), kind)
        }
    }

    /// A plain wall over the edge a→b with the inside on its left, facing out.
    public func wall(_ a: P2, _ b: P2, _ z0: Double, _ z1: Double, _ colour: String, _ kind: String) {
        if z1 - z0 < 0.01 { return }
        flat([v3(a, z0), v3(b, z0), v3(b, z1), v3(a, z1)], colour, kind)
    }

    /// Plain walls round a polygon and its holes.
    public func walls(_ poly: Geometry, _ z0: Double, _ z1: Double, _ colour: String, _ kind: String,
                      skip: ((P2, P2) -> Bool)? = nil) {
        for (a, b) in edges(poly) where !(skip?(a, b) ?? false) {
            wall(a, b, z0, z1, colour, kind)
        }
    }
}

/// Every edge of a polygon and its holes, each with the polygon's inside on
/// its left.
public func edges(_ poly: Geometry) -> [(P2, P2)] {
    let p = poly.oriented(1)
    var out: [(P2, P2)] = []
    for ring in [p.exterior] + p.interiors {
        for i in 0..<max(0, ring.count - 1) {
            let a = ring[i], b = ring[i + 1]
            if simd_length_squared(a - b) > 1e-8 { out.append((a, b)) }
        }
    }
    return out
}
