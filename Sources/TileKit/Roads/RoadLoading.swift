import Foundation
import Geometry

/// Loading: a road document in a tile's metres, as shapes for the build.
extension Roads {
    /// The document in the projection's local metres, as shapes for Ground:
    /// the roadway, white and yellow paint (not yet clipped to the roadway)
    /// and the shelters (centre, heading in radians).
    public static func load(_ doc: RoadDocument, _ p: Projecting, work: Geometry)
        -> (roadway: Geometry, white: Geometry?, yellow: Geometry?, shelters: [(P2, Double)]) {
        func m(_ q: P2) -> P2 { p.metres(lat: q.y, lon: q.x) }
        let reach = work.buffer(60)
        var add: [Geometry] = [], cut: [Geometry] = []
        for a in doc.areas {
            let poly = Geometry.polygon(a.outer.map(m), holes: a.holes.map { $0.map(m) })
            guard poly.intersects(reach) else { continue }
            if a.op == "add" { add.append(clean(poly)) } else { cut.append(clean(poly)) }
        }
        var roadway = clean(.unaryUnion(add))
        if !cut.isEmpty { roadway = clean(roadway.difference(.unaryUnion(cut))) }
        var white: [Geometry] = [], bars: [Geometry] = [], yellow: [Geometry] = [], zones: [Geometry] = []
        for var mark in doc.markings {
            mark.points = mark.points.map(m)
            mark.centre = mark.centre.map(m)
            guard let anchor = mark.centre ?? mark.points.first else { continue }
            if Geometry.point(anchor).distance(reach) > 200 { continue }
            switch mark.kind {
            case "line":
                if mark.colour == "yellow" { yellow += Markings.linePaint(mark) } else { white += Markings.linePaint(mark) }
            case "zebra":
                if let (b, z) = Markings.zebraBars(mark, roadway) {
                    bars.append(b)
                    zones.append(z)
                }
            case "zigzag":
                if let g = Markings.zigzagPaint(mark) { yellow.append(g) }
            case "letter":
                white.append(Markings.letterPaint(mark))
            default:
                break
            }
        }
        // Every other white marking is wiped from a zebra's zone.
        var w: Geometry? = white.isEmpty ? nil : .unaryUnion(white)
        if let ww = w, !zones.isEmpty { w = ww.difference(.unaryUnion(zones)) }
        if w != nil || !bars.isEmpty { w = .unaryUnion((w.map { [$0] } ?? []) + bars) }
        let near = work.buffer(10)
        let shelters = doc.shelters.compactMap { s -> (P2, Double)? in
            let c = m(s.position)
            return near.contains(c) ? (c, s.heading * .pi / 180) : nil
        }
        return (roadway, w, yellow.isEmpty ? nil : .unaryUnion(yellow), shelters)
    }
}
