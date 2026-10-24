import Foundation
import Geometry
import simd

/// The site cabins and the portable toilets.
extension ConstructionSite {
    /// Site cabins: two side by side, one more on the first, each with a window
    /// on both long sides.
    static func cabins(_ b: Builder, _ p: P2, _ heading: Double, _ seed: String) {
        let z = Level.ground
        let (_, v) = frameAxes(heading)
        let c = v3(p)
        let colours = hex(seed, 0, 2) % 2 == 1 ? ("cabin", "cabin_b") : ("cabin_b", "cabin")
        let spots = [(c - v * 0.9, z, colours.0), (c + v * 0.9, z, colours.1), (c - v * 0.9, z + 2.6, colours.1)]
        for (k, (at, z0, colour)) in spots.enumerated() {
            upright(b, P2(at.x, at.y), heading, 6.0, 1.7, z0, 2.6, colour, top: k != 0)
            for side in [-1.0, 1.0] {
                let w = at + v * (side * 0.87)
                upright(b, P2(w.x, w.y), heading, 1.4, 0.06, z0 + 1.1, 0.9, "cab_glass")
            }
        }
    }

    /// Three portable toilets in a row, blue with a white roof.
    static func toilets(_ b: Builder, _ p: P2, _ heading: Double) {
        let (u, _) = frameAxes(heading)
        for k in [-1.0, 0, 1] {
            let at = v3(p) + u * (k * 1.4)
            upright(b, P2(at.x, at.y), heading, 1.2, 1.2, Level.ground, 2.2, "cabin", top: false)
            upright(b, P2(at.x, at.y), heading, 1.32, 1.32, Level.ground + 2.2, 0.12, "cabin_b", bottom: true)
        }
    }
}
