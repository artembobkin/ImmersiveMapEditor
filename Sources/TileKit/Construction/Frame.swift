import Foundation
import Geometry
import simd

/// The concrete frame of the house being built.
extension ConstructionSite {
    /// The concrete frame of the house being built: a foundation slab, columns
    /// on a grid of about six metres, a floor slab on every storey, and the top
    /// storey half up, its columns standing free.
    static func carcass(_ b: Builder, _ p: P2, _ heading: Double, _ lx: Double, _ ly: Double, _ floors: Int) {
        let z = Level.ground
        let (u, v) = frameAxes(heading)
        let c = v3(p)
        upright(b, p, heading, lx + 0.6, ly + 0.6, z, 0.5, "concrete")
        let nx = max(2, pyRound(lx / 6) + 1), ny = max(2, pyRound(ly / 6) + 1)
        for f in 0..<floors {
            let base = z + 0.5 + Double(f) * 3.2
            let last = f == floors - 1
            for i in 0..<nx {
                for j in 0..<ny {
                    if last && (i + j) % 2 == 1 { continue }
                    let at = c + u * (-lx / 2 + 0.3 + Double(i) * (lx - 0.6) / Double(nx - 1))
                        + v * (-ly / 2 + 0.3 + Double(j) * (ly - 0.6) / Double(ny - 1))
                    upright(b, P2(at.x, at.y), heading, 0.5, 0.5, base, 2.9, "concrete", top: last)
                }
            }
            if !last { upright(b, p, heading, lx, ly, base + 2.9, 0.3, "concrete", bottom: true) }
        }
    }
}
