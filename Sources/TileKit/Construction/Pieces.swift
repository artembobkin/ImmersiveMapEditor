import Foundation
import Geometry
import simd

/// Helpers of the pieces: faces sided by where they look, cylinders and
/// cones along an axis.
extension ConstructionSite {
    /// A face's palette name by where it looks: its side of the sun, the lit
    /// tone looking up (or `top`), the shade looking down.
    static func sided(_ colour: String, _ top: String? = nil) -> (V3) -> String {
        { n in
            let family = top != nil && n.z > 0.97 ? top! : colour
            let side = n.z < -0.5 ? "shade" : abs(n.z) < 0.97 ? Palette.side(n.x, n.y) : "lit"
            return "\(family).\(side)"
        }
    }

    /// A face lying on the ground, which nothing will see.
    static func onGround(_ points: [V3]) -> Bool { points.allSatisfy { abs($0.z - Level.ground) < 1e-3 } }

    /// The rotation turning +Z onto `axis` the shortest way.
    static func rotationTo(_ axis: V3) -> simd_double3x3 {
        let a = axis.normalized
        let c = a.z
        if c > 1 - 1e-9 { return matrix_identity_double3x3 }
        if c < -1 + 1e-9 { return simd_double3x3(rows: [V3(1, 0, 0), V3(0, -1, 0), V3(0, 0, -1)]) }
        // Rodrigues about k = z × a.
        let k = V3(-a.y, a.x, 0).normalized
        let s = (1 - c * c).squareRoot()
        let t = 1 - c
        return simd_double3x3(rows: [
            V3(c + k.x * k.x * t, k.x * k.y * t - k.z * s, k.x * k.z * t + k.y * s),
            V3(k.y * k.x * t + k.z * s, c + k.y * k.y * t, k.y * k.z * t - k.x * s),
            V3(k.z * k.x * t - k.y * s, k.z * k.y * t + k.x * s, c + k.z * k.z * t),
        ])
    }

    /// A cylinder (a cone if radius2 is given) along `axis` around `centre`,
    /// capped.
    static func cylinder(_ b: Builder, _ centre: V3, _ axis: V3, _ radius: Double, _ length: Double, _ colour: String,
                          segments: Int = 8, radius2: Double? = nil, top: String? = nil) {
        let faces = cone(segments: segments, radius1: radius, radius2: radius2 ?? radius, depth: length, capEnds: true)
        let turn = rotationTo(axis)
        b.instance(faces, { turn * $0 + centre }, sided(colour, top), kind, drop: onGround)
    }
}
