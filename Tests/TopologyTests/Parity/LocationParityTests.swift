import Foundation
import Testing
import Topology

/// Point location (`PointLocator`, `RayCrossingCounter`) against GEOS's
/// stored answers of the predicates of a point: a point intersects a
/// geometry when it is not in its exterior, and is contained when it is in
/// its interior. The points are on vertices, on edges (midpoints, exactly or
/// nearly), and anywhere around. Only valid geometries (by GEOS) that are
/// not collections: for an invalid one (parts overlapping) or a collection
/// GEOS's predicates follow the relate rules (the union of the parts),
/// compared with the predicates in phase 4.
@Suite struct LocationParityTests {
    @Test func pointLocation() {
        let o = Oracles.make("LocationParityTests.pointLocation")
        defer { o.finish() }
        var intersects = ParityTally("PointLocator (GEOSIntersects of a point)")
        var contains = ParityTally("PointLocator (GEOSContains of a point)")
        var onLineApart = 0
        var r = RandomGeometries(seed: 30)
        for _ in 0..<4000 {
            let s = r.geometry()
            let g = s.topology()
            if g.isEmpty() || s.kind == .geometryCollection { continue }
            if o.predicate(.isValid, [.shape(s)]) != true { continue }
            let pts = g.getCoordinates()
            let env = g.getEnvelopeInternal()
            var probes: [Coordinate] = []
            for _ in 0..<8 {
                switch r.int(0...3) {
                case 0: probes.append(pts.randomElement(using: &r.rng)!)
                case 1:
                    let i = r.int(0...(pts.count - 1)), j = min(i + 1, pts.count - 1)
                    probes.append(Coordinate((pts[i].x + pts[j].x) / 2, (pts[i].y + pts[j].y) / 2))
                case 2:
                    let i = r.int(0...(pts.count - 1)), j = min(i + 1, pts.count - 1)
                    let t = r.double(0...1)
                    let c = Coordinate(pts[i].x + t * (pts[j].x - pts[i].x), pts[i].y + t * (pts[j].y - pts[i].y))
                    probes.append(Coordinate(c.x + Double(r.int(-2...2)) * c.x.ulp, c.y))
                default:
                    probes.append(Coordinate(r.double(env.minX...max(env.maxX, env.minX + 1e-9)),
                                             r.double(env.minY...max(env.maxY, env.minY + 1e-9))))
                }
            }
            for p in probes {
                var locator = PointLocator()
                let loc = locator.locate(p, g)
                let point = Shape(kind: .point, coordinates: [p.x, p.y])
                let gi = o.predicate(.intersects, [.shape(point), .shape(s)])
                let gc = o.predicate(.contains, [.shape(s), .shape(point)])
                // GEOS 3.13's PointLocator tests a polygon's rings with
                // `isOnLine` before counting crossings, as the port does, and
                // its predicates count crossings only. The two disagree for a
                // point a few subnormals off a vertex, whose orientation to the
                // segment there rounds to collinear: counted apart, checked to be
                // exactly that case.
                if (loc != Location.exterior) != gi && loc == Location.boundary && gi == false,
                   let poly = g as? Polygon ?? (g as? MultiPolygon)?.geometries.first as? Polygon,
                   PointLocation.isOnLine(p, poly.shell.points) || poly.holes.contains(where: { PointLocation.isOnLine(p, $0.points) }),
                   RayCrossingCounter.locatePointInRing(p, poly.shell.points) == Location.exterior {
                    onLineApart += 1
                    continue
                }
                intersects.check((loc != Location.exterior) == gi, "\(s) \(p): location \(loc), GEOS intersects \(String(describing: gi))")
                contains.check((loc == Location.interior) == gc, "\(s) \(p): location \(loc), GEOS contains \(String(describing: gc))")
            }
        }
        intersects.report()
        contains.report()
        print("parity PointLocator: \(onLineApart) points on a ring by isOnLine and outside by the crossings, as GEOS's own two")
    }
}
