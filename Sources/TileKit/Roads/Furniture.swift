import Foundation
import Geometry

// Street furniture, low-poly in the palette's own colours: a bus shelter at
// every shelter of the road document (`RoadDocument`), standing on the ground
// behind the kerb and along it: corner posts, glass at the back and the
// sides, a white roof, a bench inside, the stop's blue sign on a pole by the
// kerb. The seeding places one behind every bus stop's zigzag, the editor
// moves them.

private let kind = "furniture"

/// A shelter at each (centre, heading in radians), the road on its left.
public func buildFurniture(_ b: Builder, shelters: [(P2, Double)]) -> [String: Int] {
    for (centre, heading) in shelters {
        shelter(b, centre, heading, P2(-sin(heading), cos(heading)))
    }
    return ["bus_shelters": shelters.count]
}

/// A bus shelter centred on `centre`, its length along `heading`, open to the
/// road on the side `toRoad` points to.
func shelter(_ b: Builder, _ centre: P2, _ heading: Double, _ toRoad: P2) {
    let (lx, ly, h) = shelterSize
    let z = Level.ground
    var heading = heading
    var (u, v) = frameAxes(heading)
    if v.x * toRoad.x + v.y * toRoad.y < 0 {
        v = -v
        heading += .pi
        u = -u
    }
    let c = v3(centre)
    func xy(_ p: V3) -> P2 { P2(p.x, p.y) }
    for su in [-1.0, 1.0] {
        for sv in [-1.0, 1.0] {
            let at = c + u * (su * (lx / 2 - 0.08)) + v * (sv * (ly / 2 - 0.08))
            upright(b, xy(at), heading, 0.12, 0.12, z, h, "frame", kind, top: false)
        }
    }
    let glass = c - v * (ly / 2 - 0.08)
    upright(b, xy(glass), heading, lx - 0.3, 0.05, z + 0.2, h - 0.35, "cab_glass", kind)
    for su in [-1.0, 1.0] {
        let side = c + u * (su * (lx / 2 - 0.08)) - v * (ly * 0.2)
        upright(b, xy(side), heading, 0.05, ly * 0.55, z + 0.2, h - 0.35, "cab_glass", kind)
    }
    upright(b, xy(c), heading, lx + 0.3, ly + 0.3, z + h, 0.16, "cabin_b", kind, bottom: true)
    let seat = c - v * (ly / 2 - 0.45)
    upright(b, xy(seat), heading, lx * 0.5, 0.42, z + 0.42, 0.07, "bench", kind, bottom: true)
    for su in [-1.0, 1.0] {
        let leg = seat + u * (su * lx * 0.2)
        upright(b, xy(leg), heading, 0.08, 0.3, z, 0.42, "frame", kind, top: false)
    }
    let pole = c + u * (lx / 2 + 0.9) + v * (ly / 2 - 0.1)
    bar(b, V3(pole.x, pole.y, z), V3(pole.x, pole.y, z + 2.9), 0.08, "frame", kind)
    upright(b, xy(pole), heading + .pi / 2, 0.05, 0.6, z + 2.3, 0.55, "sign", kind, bottom: true)
}
