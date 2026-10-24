import Foundation
import Testing
import Topology
import geos

/// The recorded calls of `Geometry` on real data replayed on the port and on
/// GEOS, for the functions ported so far: the same results, bit for bit
/// (geometries in GEOS's normal form).
@Suite(.enabled(if: Recording.available, "no recordings in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct ReplayTests {
    /// A recording's geometries, read once by each side.
    final class Inputs {
        let recording: Recording
        let oracle: GEOSOracle
        var port: [UInt32: Topology.Geometry] = [:]
        var geos: [UInt32: GEOSGeom] = [:]

        init(_ r: Recording, _ o: GEOSOracle) {
            recording = r
            oracle = o
        }

        func port(_ id: UInt32) -> Topology.Geometry {
            if let g = port[id] { return g }
            let g = try! WKBReader().read(recording.geometries[id]!)
            port[id] = g
            return g
        }

        func geos(_ id: UInt32) -> GEOSGeom {
            if let g = geos[id] { return g }
            let g = oracle.read(wkb: recording.geometries[id]!)!
            geos[id] = g
            return g
        }
    }

    /// Replays every call named `name` in every recording.
    static func replay(_ name: String, _ check: (Inputs, Recording.Call, inout ParityTally) -> Void) -> ParityTally {
        let o = GEOSOracle()
        var tally = ParityTally("replay \(name)")
        for r in (try? Recording.load()) ?? [] {
            let inputs = Inputs(r, o)
            for c in r.calls where c.name == name { check(inputs, c, &tally) }
        }
        return tally
    }

    static func unary(_ name: String, _ mine: @escaping (Topology.Geometry) -> Topology.Geometry,
                      _ geos: @escaping (GEOSGeom) -> GEOSGeom?) -> ParityTally {
        replay(name) { inputs, c, tally in
            let id = c.geometries[0]
            let m = mine(inputs.port(id))
            guard let g = geos(inputs.geos(id)) else { return tally.check(false, "\(name) #\(id): GEOS failed") }
            let (a, b) = inputs.oracle.normalizedShapes(m, g)
            tally.check(a == b, "\(name) #\(id): port \(a) GEOS \(b)")
        }
    }

    static func measure(_ name: String, _ mine: @escaping (Topology.Geometry) -> Double, _ geos: @escaping (GEOSGeom) -> Double?) -> ParityTally {
        replay(name) { inputs, c, tally in
            let id = c.geometries[0]
            let m = mine(inputs.port(id)), g = geos(inputs.geos(id))
            tally.check(m.bitPattern == g?.bitPattern, "\(name) #\(id): \(m) vs \(String(describing: g))")
        }
    }

    @Test func area() { ReplayTests.measure("area", { $0.getArea() }, { $0.area }).report() }
    @Test func length() { ReplayTests.measure("length", { $0.getLength() }, { $0.length }).report() }

    @Test func bounds() {
        ReplayTests.replay("bounds") { inputs, c, tally in
            let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
            let e = p.getEnvelopeInternal()
            let mine = p.isEmpty() ? [0.0, 0, 0, 0] : [e.minX, e.minY, e.maxX, e.maxY]
            var v = [0.0, 0, 0, 0]
            if !g.isEmpty {
                GEOSGeom_getXMin_r(g.handle, g.ptr, &v[0])
                GEOSGeom_getYMin_r(g.handle, g.ptr, &v[1])
                GEOSGeom_getXMax_r(g.handle, g.ptr, &v[2])
                GEOSGeom_getYMax_r(g.handle, g.ptr, &v[3])
            }
            tally.check(mine.map(\.bitPattern) == v.map(\.bitPattern), "#\(c.geometries[0]): \(mine) vs \(v)")
        }.report()
    }

    @Test func centroid() { ReplayTests.unary("centroid", { $0.getCentroid() }, { $0.unary(GEOSGetCentroid_r) }).report() }
    @Test func representativePoint() {
        ReplayTests.unary("representativePoint", { $0.getInteriorPoint() }, { $0.unary(GEOSPointOnSurface_r) }).report()
    }
    @Test func convexHull() { ReplayTests.unary("convexHull", { $0.convexHull() }, { $0.unary(GEOSConvexHull_r) }).report() }
    @Test func boundary() { ReplayTests.unary("boundary", { $0.getBoundary() }, { $0.unary(GEOSBoundary_r) }).report() }
    @Test func minimumRotatedRectangle() {
        ReplayTests.unary("minimumRotatedRectangle", { MinimumAreaRectangle.getMinimumRectangle($0) },
                          { $0.unary(GEOSMinimumRotatedRectangle_r) }).report()
    }

    /// Every recorded geometry read from its WKB by the port is GEOS's.
    @Test func wkbReading() {
        let o = GEOSOracle()
        var tally = ParityTally("replay WKB reading")
        for r in (try? Recording.load()) ?? [] {
            for (id, wkb) in r.geometries {
                let p = try? WKBReader().read(wkb)
                tally.check(p.map(Shape.init) == o.read(wkb: wkb)?.shape, "\(r.name) #\(id)")
            }
        }
        tally.report()
    }
}

/// The recorded trees (`STRtree.init`) rebuilt on both sides, their
/// recorded queries and nearest searches replayed. The nearest item is found
/// with GEOS's distance on both sides (the port's comes in phase 4).
@Suite(.enabled(if: Recording.available, "no recordings in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct STRtreeReplayTests {
    @Test func treesQueriesAndNearest() {
        let o = GEOSOracle()
        var query = ParityTally("replay STRtree.query")
        var nearest = ParityTally("replay STRtree.nearest")
        for r in (try? Recording.load()) ?? [] {
            let inputs = ReplayTests.Inputs(r, o)
            var trees: [Double: (STRtree<Int>, STRtreeParityTests.GEOSTree)] = [:]
            for c in r.calls {
                switch c.name {
                case "STRtree.init":
                    let port = STRtree<Int>(nodeCapacity: 10, tieOrder: .geos)
                    for (i, id) in c.geometries.enumerated() { port.insert(inputs.port(id).getEnvelopeInternal(), i) }
                    trees[c.numbers[0]] = (port, STRtreeParityTests.GEOSTree(o, c.geometries.map { inputs.geos($0) }))
                case "STRtree.query":
                    guard let (port, geos) = trees[c.numbers[0]] else { continue }
                    let g = inputs.geos(c.geometries[0])
                    let mine = port.query(inputs.port(c.geometries[0]).getEnvelopeInternal()).sorted()
                    query.check(mine == geos.query(g), "\(r.name) #\(c.geometries[0])")
                case "STRtree.nearest":
                    guard let (port, geos) = trees[c.numbers[0]] else { continue }
                    let g = inputs.geos(c.geometries[0])
                    let p = inputs.port(c.geometries[0])
                    let mine = geos.items.isEmpty ? nil : port.nearestNeighbour(p.getEnvelopeInternal(), -1) { i, _ in
                        geos.items[i].measure(g, GEOSDistance_r) ?? .nan
                    }
                    nearest.check(mine == geos.nearest(g), "\(r.name) #\(c.geometries[0]): \(String(describing: mine)) vs \(String(describing: geos.nearest(g)))")
                default: break
                }
            }
        }
        query.report()
        nearest.report()
    }
}
