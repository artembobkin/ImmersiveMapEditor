import Foundation
import Geometry
import simd

/// The site's fence.
extension ConstructionSite {
    /// Fence panels along the inside of the site's edge, sided like a wall, a
    /// post every `fencePost` and at every corner standing above them, and a
    /// light rail on top that outlines the site from above, as a cornice
    /// outlines a building. Left out where a building stands on the edge.
    static func buildFence(_ b: Builder, _ earth: Geometry, _ footprint: Geometry) {
        let keepOut = footprint.buffer(0.4)
        let inset = earth.buffer(-fenceThick, join: .mitre)
        var rings: [Geometry] = []
        for p in inset.polygons {
            rings.append(.lineString(p.exterior))
            for r in p.interiors where Geometry.polygon(r).area > 50 { rings.append(.lineString(r)) }
        }
        let line = Geometry.unaryUnion(rings).difference(keepOut).lineMerge()
        let pieces = line.lines.filter { $0.length > 1.0 }
        let z0 = Level.ground
        let z1 = z0 + fenceHeight
        let z2 = z1 + fenceRail
        for piece in pieces {
            slab(b, piece.buffer(fenceThick / 2, cap: .flat, join: .mitre), z0, z1, "fence")
            let rail = piece.buffer(fenceThick / 2 + 0.06, cap: .flat, join: .mitre)
            slab(b, rail, z1, z2, "fence_rail", down: true)
            for p in posts(piece) {
                upright(b, p, 0.0, 0.3, 0.3, z0, fenceHeight + fenceRail + 0.25, "fence_post")
            }
        }
    }

    /// A shape extruded from z0 to z1, its walls sided, its top lit, its
    /// underside closed if asked for.
    static func slab(_ b: Builder, _ shape: Geometry, _ z0: Double, _ z1: Double, _ colour: String, down: Bool = false) {
        for p in shape.polygons {
            for (a, c) in edges(p) {
                b.paint([v3(a, z0), v3(c, z0), v3(c, z1), v3(a, z1)], colour, kind)
            }
            b.fill(p, z1, colour, kind)
            if down { b.fill(p, z0, colour, kind, down: true) }
        }
    }

    /// Where a fence's posts stand: both ends, every corner, and evenly between
    /// them no more than `fencePost` apart.
    static func posts(_ line: Geometry) -> [P2] {
        let coords = line.coords
        var stops = [0.0]
        var run = 0.0
        for i in 1..<coords.count {
            run += simd_distance(coords[i - 1], coords[i])
            if i < coords.count - 1 {
                let a = coords[i - 1], c = coords[i], d = coords[i + 1]
                let turn = abs(atan2(d.y - c.y, d.x - c.x) - atan2(c.y - a.y, c.x - a.x))
                if min(turn, 2 * .pi - turn) < 15 * .pi / 180 { continue }
            }
            stops.append(run)
        }
        var spots: [Double] = []
        for (s0, s1) in zip(stops, stops.dropFirst()) {
            let n = max(1, Int(((s1 - s0) / fencePost).rounded(.up)))
            spots += (0..<n).map { s0 + (s1 - s0) * Double($0) / Double(n) }
        }
        spots.append(line.length)
        return spots.map { line.interpolate($0).xy }
    }
}
