import Foundation
import Geometry
import simd

/// The tower crane.
extension ConstructionSite {
    /// A tower crane: a square lattice mast, the slewing head, the jib along
    /// `turn` with its trolley and hook, the counter-jib with its weights, and
    /// the ties from the mast's top.
    static func crane(_ b: Builder, _ p: P2, _ turn: Double, _ height: Double) {
        let z = Level.ground
        upright(b, p, 0, 4.5, 4.5, z, 0.8, "concrete")
        let base = z + 0.8
        let top = base + height
        let h = mast / 2
        let corners = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { P2(p.x + $0.0 * h, p.y + $0.1 * h) }
        for c in corners { bar(b, v3(c, base), v3(c, top), 0.22, "crane") }
        let rungs = Int(height / 3.0)
        for k in 0...rungs {
            let zk = base + height * Double(k) / Double(rungs)
            for i in 0..<4 {
                let a = corners[i], c = corners[(i + 1) % 4]
                bar(b, v3(a, zk), v3(c, zk), 0.12, "crane")
                if k < rungs {
                    let z1 = base + height * Double(k + 1) / Double(rungs)
                    let (lo, hi) = k % 2 == 0 ? (a, c) : (c, a)
                    bar(b, v3(lo, zk), v3(hi, z1), 0.1, "crane")
                }
            }
        }
        // The head turns on the mast.
        let u = V3(cos(turn), sin(turn), 0)
        let v = V3(-u.y, u.x, 0)
        upright(b, p, turn, 2.6, 2.6, top, 1.4, "crane", bottom: true)
        let cab = v3(p) + u * 0.6 + v * 2.0
        upright(b, P2(cab.x, cab.y), turn, 2.0, 1.4, top + 0.1, 1.8, "cabin_b", bottom: true)
        let glass = cab + u * 1.02
        upright(b, P2(glass.x, glass.y), turn, 0.08, 1.2, top + 0.9, 0.8, "cab_glass")
        let deck = top + 1.4
        // Jib: two lower chords, one upper, zigzag between.
        let root = v3(p, deck)
        let tip = root + u * craneJib
        for side in [-0.6, 0.6] { bar(b, root + v * side, tip + v * side, 0.18, "crane") }
        bar(b, root + V3(0, 0, 1.3), tip + V3(0, 0, 0.4), 0.18, "crane")
        let panels = Int(craneJib / 3.0)
        for k in 0..<panels {
            let a = root + u * (craneJib * Double(k) / Double(panels))
            let c = root + u * (craneJib * Double(k + 1) / Double(panels))
            let riseA = 1.3 - 0.9 * Double(k) / Double(panels)
            let riseC = 1.3 - 0.9 * Double(k + 1) / Double(panels)
            for side in [-0.6, 0.6] {
                let (lo, hi) = k % 2 == 0 ? (a, c) : (c, a)
                let rHi = k % 2 == 0 ? riseC : riseA
                bar(b, lo + v * side, hi + V3(0, 0, rHi), 0.08, "crane")
            }
        }
        // Counter-jib and its weights.
        let back = root - u * craneCounter
        bar(b, root, back, 0.9, "crane")
        let weight = root - u * (craneCounter - 1.4)
        upright(b, P2(weight.x, weight.y), turn, 2.2, 2.4, deck - 1.6, 2.0, "concrete", bottom: true)
        // The mast's top and its ties.
        let peak = root + V3(0, 0, 7.0)
        for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
            bar(b, root + V3(sx * 0.6, sy * 0.6, 0.45), peak, 0.16, "crane")
        }
        bar(b, peak, root + u * (craneJib * 0.65) + V3(0, 0, 1.0), 0.07, "crane")
        bar(b, peak, back + V3(0, 0, 0.45), 0.07, "crane")
        // Trolley, cable, hook.
        let reach = root + u * (craneJib * 0.55)
        upright(b, P2(reach.x, reach.y), turn, 1.2, 1.6, deck - 0.5, 0.5, "machine_dark", bottom: true)
        let hookZ = Level.ground + height * 0.45
        bar(b, V3(reach.x, reach.y, deck - 0.5), V3(reach.x, reach.y, hookZ + 0.8), 0.06, "machine_dark")
        upright(b, P2(reach.x, reach.y), turn, 0.7, 0.7, hookZ, 0.8, "machine", bottom: true)
    }
}
