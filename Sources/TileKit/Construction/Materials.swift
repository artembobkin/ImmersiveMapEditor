import Foundation
import Geometry
import simd

/// Materials and earthworks: piles, mounds, slabs, bricks, pipes, rings.
extension ConstructionSite {
    /// A pile of sand or gravel: a cone of seven sides.
    static func pile(_ b: Builder, _ p: P2, _ colour: String, _ radius: Double, _ height: Double) {
        cylinder(b, v3(p, Level.ground + height / 2), V3(0, 0, 1), radius, height, colour, segments: 7, radius2: 0.0)
    }

    /// A long mound of dug earth with a flat top, along `heading`.
    static func mound(_ b: Builder, _ p: P2, _ heading: Double, _ radius: Double, _ height: Double) {
        let faces = cone(segments: 8, radius1: radius, radius2: radius * 0.35, depth: height, capEnds: true)
        let (u, v) = frameAxes(heading)
        let m = simd_double3x3(rows: [V3(u.x * 1.5, v.x, 0), V3(u.y * 1.5, v.y, 0), V3(0, 0, 1)])
        let centre = v3(p, Level.ground + height / 2)
        b.instance(faces, { m * $0 + centre }, sided("soil"), kind, drop: onGround)
    }

    /// A stack of concrete slabs, each laid a little askew.
    static func slabs(_ b: Builder, _ p: P2, _ heading: Double, _ count: Int, _ seed: String) {
        for k in 0..<count {
            let skew = (Double(hex(seed, 2 * k, 2 * k + 2)) / 255 - 0.5) * (8 * .pi / 180)
            upright(b, p, heading + skew, 6.0, 1.5, Level.ground + Double(k) * 0.24, 0.24, "concrete")
        }
    }

    /// Six pallets of bricks, three by two.
    static func bricks(_ b: Builder, _ p: P2, _ heading: Double) {
        let (u, v) = frameAxes(heading)
        for i in [-1.0, 0, 1] {
            for j in [-0.6, 0.6] {
                let at = v3(p) + u * (i * 1.3) + v * j
                upright(b, P2(at.x, at.y), heading, 1.2, 1.0, Level.ground, 0.15, "pallet")
                upright(b, P2(at.x, at.y), heading, 1.1, 0.9, Level.ground + 0.15, 0.85, "brick")
            }
        }
    }

    /// Steel pipes stacked three, two, one.
    static func pipes(_ b: Builder, _ p: P2, _ heading: Double) {
        let (u, v) = frameAxes(heading)
        let r = 0.32
        for (count, z) in [(3, r), (2, r * 2.7), (1, r * 4.4)] {
            for k in 0..<count {
                let at = v3(p, Level.ground + z) + v * ((Double(k) - Double(count - 1) / 2) * r * 2.05)
                cylinder(b, at, u, r, 6.0, "pipe", segments: 6)
            }
        }
    }

    /// Concrete well rings standing in a row, dark inside.
    static func rings(_ b: Builder, _ p: P2, _ heading: Double) {
        let (u, _) = frameAxes(heading)
        for k in [-1.0, 0, 1] {
            let at = v3(p, Level.ground + 0.45) + u * (k * 1.65)
            cylinder(b, at, V3(0, 0, 1), 0.75, 0.9, "concrete", segments: 8, top: "machine_dark")
        }
    }
}
