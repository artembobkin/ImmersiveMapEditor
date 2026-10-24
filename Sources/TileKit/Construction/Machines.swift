import Foundation
import Geometry
import simd

/// The machines: an excavator, trucks, a concrete mixer, a bulldozer.
extension ConstructionSite {
    /// A tracked excavator: two tracks, the turning body with its cab and
    /// counterweight, the boom and stick, the bucket on the ground.
    static func excavator(_ b: Builder, _ p: P2, _ heading: Double, _ slew: Double) {
        let z = Level.ground
        let u = V3(cos(heading), sin(heading), 0)
        let v = V3(-u.y, u.x, 0)
        let c = v3(p)
        for side in [-1.2, 1.2] {
            let t = c + v * side
            upright(b, P2(t.x, t.y), heading, 4.2, 0.8, z, 0.9, "machine_dark")
        }
        upright(b, p, heading, 2.0, 1.6, z + 0.2, 0.9, "machine_dark", top: false)
        let turn = heading + slew
        let bu = V3(cos(turn), sin(turn), 0)
        let bv = V3(-bu.y, bu.x, 0)
        upright(b, p, turn, 3.6, 2.6, z + 1.1, 1.1, "machine", bottom: true)
        let weight = c - bu * 1.5
        upright(b, P2(weight.x, weight.y), turn, 0.8, 2.6, z + 2.2, 0.5, "machine")
        let cab = c + bu * 0.9 + bv * 0.65
        upright(b, P2(cab.x, cab.y), turn, 1.4, 1.1, z + 2.2, 1.4, "cab_glass", top: false)
        upright(b, P2(cab.x, cab.y), turn, 1.5, 1.2, z + 3.6, 0.14, "machine", bottom: true)
        let pivot = c + bu * 1.6 - bv * 0.4 + V3(0, 0, z + 1.9)
        let elbow = c + bu * 4.4 - bv * 0.4 + V3(0, 0, z + 4.6)
        let wrist = c + bu * 6.2 - bv * 0.4 + V3(0, 0, z + 1.2)
        bar(b, pivot, elbow, 0.5, "machine")
        bar(b, elbow, wrist, 0.38, "machine")
        upright(b, P2(wrist.x, wrist.y), turn, 0.9, 1.0, z, 0.9, "machine_dark")
    }

    /// The chassis of a truck eight metres long: wheels on `axles` (along the
    /// truck from its middle), the frame, the cab at the front with its
    /// windscreen. Returns the axes and the middle on the ground.
    static func truck(_ b: Builder, _ p: P2, _ heading: Double, _ axles: [Double]) -> (V3, V3, V3) {
        let z = Level.ground
        let (u, v) = frameAxes(heading)
        let c = v3(p, z)
        for x in axles {
            for side in [-1.05, 1.05] {
                cylinder(b, c + u * x + v * side + V3(0, 0, 0.55), v, 0.55, 0.4, "machine_dark", segments: 7)
            }
        }
        upright(b, p, heading, 7.6, 1.8, z + 0.6, 0.4, "machine_dark", bottom: true)
        let cab = c + u * 3.0
        upright(b, P2(cab.x, cab.y), heading, 1.6, 2.3, z + 1.0, 1.9, "machine")
        let glass = c + u * 3.81
        upright(b, P2(glass.x, glass.y), heading, 0.06, 2.0, z + 2.0, 0.7, "cab_glass")
        return (u, v, c)
    }

    /// A dump truck, its body full of earth heaped over the top.
    static func dumpTruck(_ b: Builder, _ p: P2, _ heading: Double) {
        let (u, _, c) = truck(b, p, heading, [-2.6, -1.3, 2.6])
        let body = c - u * 0.95
        upright(b, P2(body.x, body.y), heading, 5.6, 2.4, c.z + 1.0, 1.4, "crane", top: false)
        upright(b, P2(body.x, body.y), heading, 5.3, 2.1, c.z + 1.0, 1.6, "soil")
    }

    /// A concrete mixer truck, its drum tilted up to the back.
    static func mixer(_ b: Builder, _ p: P2, _ heading: Double) {
        let (u, _, c) = truck(b, p, heading, [-2.6, -1.3, 2.6])
        let tilt = 14.0 * .pi / 180
        let axis = -u * cos(tilt) + V3(0, 0, sin(tilt))
        cylinder(b, c - u * 0.9 + V3(0, 0, 2.35), axis, 1.2, 4.2, "cabin_b", radius2: 0.6)
    }

    /// A bulldozer: tracks, the body, the cab, the blade in front.
    static func bulldozer(_ b: Builder, _ p: P2, _ heading: Double) {
        let z = Level.ground
        let (u, v) = frameAxes(heading)
        let c = v3(p)
        for side in [-1.1, 1.1] {
            let t = c + v * side
            upright(b, P2(t.x, t.y), heading, 3.6, 0.7, z, 0.8, "machine_dark")
        }
        let body = c - u * 0.2
        upright(b, P2(body.x, body.y), heading, 2.8, 1.6, z + 0.8, 1.1, "crane", bottom: true)
        let cab = c - u * 0.7
        upright(b, P2(cab.x, cab.y), heading, 1.3, 1.4, z + 1.9, 1.2, "cab_glass", top: false)
        upright(b, P2(cab.x, cab.y), heading, 1.4, 1.5, z + 3.1, 0.14, "crane", bottom: true)
        let blade = c + u * 2.3
        upright(b, P2(blade.x, blade.y), heading, 0.3, 3.4, z, 1.2, "crane")
        for side in [-0.7, 0.7] {
            let a = c + u * 1.1 + v * side + V3(0, 0, z + 1.0)
            bar(b, a, blade - u * 0.15 + v * side + V3(0, 0, z + 0.6), 0.2, "machine_dark")
        }
    }
}
