import Foundation
import Testing
import Topology
import geos

/// The time of every recorded call of one whole tile, the port against
/// GEOS, function by function and in total (Docs/PortingGoal.md,
/// "Performance": a tile at most 1.5 times GEOS's time). Each call is timed
/// alone on each side, its result made and freed inside the measure. Run
/// with `TOPOLOGY_SPEED=1` in an optimized build
/// (`swift test -c release -Xswiftc -enable-testing --filter SpeedTests`);
/// `TOPOLOGY_SPEED_RECORDING` names the recording (`tiles/19808_10243`).
@Suite(.enabled(if: Recording.available && ProcessInfo.processInfo.environment["TOPOLOGY_SPEED"] == "1"))
struct SpeedTests {
    struct Timing {
        var calls = 0
        var port = Duration.zero
        var geos = Duration.zero
    }

    static func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    @Test func tile() throws {
        let name = ProcessInfo.processInfo.environment["TOPOLOGY_SPEED_RECORDING"] ?? "tiles/19808_10243"
        guard let file = Recording.files().first(where: { $0.name == name }) else { Issue.record("no recording \(name)"); return }
        let r = try Recording(url: file.url, name: name)
        let o = GEOSOracle()
        let inputs = ReplayTests.Inputs(r, o)
        // Every geometry read on both sides first, so reading is not timed.
        for id in r.geometries.keys { _ = inputs.port(id); _ = inputs.geos(id) }
        let clock = ContinuousClock()
        var timings: [String: Timing] = [:]
        var prepared: [Double: (PreparedGeometry, GEOSPrepared)] = [:]
        var trees: [Double: (STRtree<Int>, STRtreeParityTests.GEOSTree, [Topology.Geometry])] = [:]
        var sink = 0
        func time(_ name: String, _ port: () -> Void, _ geos: () -> Void) {
            var t = timings[name] ?? Timing()
            t.calls += 1
            t.geos += clock.measure(geos)
            t.port += clock.measure(port)
            timings[name] = t
        }
        func unary(_ c: Recording.Call, _ mine: (Topology.Geometry) throws -> Topology.Geometry, _ theirs: (GEOSGeom) -> GEOSGeom?) {
            let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
            time(c.name, { if let m = try? mine(p) { sink &+= m.getNumPoints() } }, { if let x = theirs(g) { sink &+= x.isEmpty ? 0 : 1 } })
        }
        func binary(_ c: Recording.Call, _ mine: (Topology.Geometry, Topology.Geometry) throws -> Topology.Geometry,
                    _ theirs: (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> OpaquePointer?) {
            let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
            time(c.name, { if let m = try? mine(p[0], p[1]) { sink &+= m.getNumPoints() } },
                 { if let x = g[0].binary(g[1], theirs) { sink &+= x.isEmpty ? 0 : 1 } })
        }
        func predicate(_ c: Recording.Call, _ mine: (Topology.Geometry, Topology.Geometry) throws -> Bool,
                       _ theirs: (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> Int8) {
            let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
            time(c.name, { if (try? mine(p[0], p[1])) == true { sink &+= 1 } }, { if g[0].predicate(g[1], theirs) == true { sink &+= 1 } })
        }
        for c in r.calls {
            let n = c.numbers
            switch c.name {
            case "intersects": predicate(c, { try $0.intersects($1) }, GEOSIntersects_r)
            case "contains": predicate(c, { try $0.contains($1) }, GEOSContains_r)
            case "within": predicate(c, { try $0.within($1) }, GEOSWithin_r)
            case "intersection": binary(c, { try $0.intersection($1) }, GEOSIntersection_r)
            case "difference": binary(c, { try $0.difference($1) }, GEOSDifference_r)
            case "union": binary(c, { try $0.union($1) }, GEOSUnion_r)
            case "unaryUnion":
                guard let p = OverlayReplayTests.collection(c.geometries.map { inputs.port($0) }, .default) else { continue }
                let g = o.geos(p)
                time(c.name, { if let m = try? p.union() { sink &+= m.getNumPoints() } }, { if let x = g.unaryUnion { sink &+= x.isEmpty ? 0 : 1 } })
            case "buffer":
                unary(c, { try $0.buffer(n[0], quadSegs: Int(n[1]), endCapStyle: Int(n[2]), joinStyle: Int(n[3]), mitreLimit: n[4]) }) {
                    $0.oracle.wrap(GEOSBufferWithStyle_r($0.handle, $0.ptr, n[0], Int32(n[1]), Int32(n[2]), Int32(n[3]), n[4]))
                }
            case "offsetCurve":
                unary(c, { try $0.offsetCurve(n[0], quadSegs: Int(n[1]), joinStyle: Int(n[2]), mitreLimit: n[3]) }) {
                    $0.oracle.wrap(GEOSOffsetCurve_r($0.handle, $0.ptr, n[0], Int32(n[1]), Int32(n[2]), n[3]))
                }
            case "makeValid": unary(c, { try $0.makeValid() }) { $0.unary(GEOSMakeValid_r) }
            case "setPrecision": unary(c, { try $0.setPrecision(n[0]) }) { $0.oracle.wrap(GEOSGeom_setPrecision_r($0.handle, $0.ptr, n[0], 0)) }
            case "simplify": unary(c, { try $0.topologyPreserveSimplify(n[0]) }) { $0.unary(GEOSTopologyPreserveSimplify_r, n[0]) }
            case "lineMerge": unary(c, { try $0.lineMerge() }) { $0.unary(GEOSLineMerge_r) }
            case "constrainedDelaunay": unary(c, { try ConstrainedDelaunayTriangulator.triangulate($0) }) { $0.unary(GEOSConstrainedDelaunayTriangulation_r) }
            case "centroid": unary(c, { $0.getCentroid() }) { $0.unary(GEOSGetCentroid_r) }
            case "representativePoint": unary(c, { $0.getInteriorPoint() }) { $0.unary(GEOSPointOnSurface_r) }
            case "convexHull": unary(c, { $0.convexHull() }) { $0.unary(GEOSConvexHull_r) }
            case "boundary": unary(c, { $0.getBoundary() }) { $0.unary(GEOSBoundary_r) }
            case "envelope": unary(c, { $0.getEnvelope() }) { $0.unary(GEOSEnvelope_r) }
            case "minimumRotatedRectangle": unary(c, { MinimumAreaRectangle.getMinimumRectangle($0) }) { $0.unary(GEOSMinimumRotatedRectangle_r) }
            case "interpolate":
                unary(c, { try $0.interpolate(n[0], normalized: n[1] != 0) }) { TriangulationParityTests.geosInterpolate($0, n[0], n[1] != 0) }
            case "polygonize":
                let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
                time(c.name, { if let m = try? Topology.Geometry.polygonize(p) { sink &+= m.getNumPoints() } }, {
                    var ptrs: [OpaquePointer?] = g.map { $0.ptr }
                    if let x = o.wrap(GEOSPolygonize_r(o.handle, &ptrs, UInt32(ptrs.count))) { sink &+= x.isEmpty ? 0 : 1 }
                })
            case "isValid":
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                time(c.name, { if (try? p.isValid()) == true { sink &+= 1 } }, { if g.predicate(GEOSisValid_r) == true { sink &+= 1 } })
            case "area":
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                time(c.name, { sink &+= Int(p.getArea().bitPattern & 1) }, { sink &+= Int((g.area ?? 0).bitPattern & 1) })
            case "length":
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                time(c.name, { sink &+= Int(p.getLength().bitPattern & 1) }, { sink &+= Int((g.length ?? 0).bitPattern & 1) })
            case "bounds":
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                time(c.name, { sink &+= Int(p.getEnvelopeInternal().minX.bitPattern & 1) }, {
                    var v = 0.0
                    GEOSGeom_getXMin_r(g.handle, g.ptr, &v)
                    sink &+= Int(v.bitPattern & 1)
                })
            case "distance":
                let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
                time(c.name, { sink &+= Int(p[0].distance(p[1]).bitPattern & 1) }, { sink &+= Int((g[0].measure(g[1], GEOSDistance_r) ?? 0).bitPattern & 1) })
            case "nearestPoints":
                let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
                time(c.name, { sink &+= DistanceOp.nearestPoints(p[0], p[1])?.count ?? 0 }, {
                    if let s = GEOSNearestPoints_r(o.handle, g[0].ptr, g[1].ptr) { GEOSCoordSeq_destroy_r(o.handle, s); sink &+= 1 }
                })
            case "project":
                let p = c.geometries.map { inputs.port($0) }, g = c.geometries.map { inputs.geos($0) }
                time(c.name, { sink &+= Int(((try? p[0].project(p[1])) ?? 0).bitPattern & 1) }, { sink &+= Int(GEOSProject_r(o.handle, g[0].ptr, g[1].ptr).bitPattern & 1) })
            case "Prepared.init":
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                var made: (PreparedGeometry, GEOSPrepared)?
                var port: PreparedGeometry?, geos: GEOSPrepared?
                time(c.name, { port = PreparedGeometryFactory.prepare(p) }, { geos = g.prepared() })
                made = (port!, geos!)
                prepared[n[0]] = made
            case "Prepared.contains", "Prepared.intersects":
                guard let (pp, gp) = prepared[n[0]] else { continue }
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                let isContains = c.name == "Prepared.contains"
                time(c.name, { if (try? (isContains ? pp.contains(p) : pp.intersects(p))) == true { sink &+= 1 } },
                     { if gp.predicate(g, isContains ? GEOSPreparedContains_r : GEOSPreparedIntersects_r) == true { sink &+= 1 } })
            case "STRtree.init":
                let ps = c.geometries.map { inputs.port($0) }, gs = c.geometries.map { inputs.geos($0) }
                var port: STRtree<Int>?, geos: STRtreeParityTests.GEOSTree?
                time(c.name, {
                    let t = STRtree<Int>(nodeCapacity: 10, tieOrder: .geos)
                    for (i, g) in ps.enumerated() { t.insert(g.getEnvelopeInternal(), i) }
                    port = t
                }, { geos = STRtreeParityTests.GEOSTree(o, gs) })
                trees[n[0]] = (port!, geos!, ps)
            case "STRtree.query":
                guard let (pt, gt, _) = trees[n[0]] else { continue }
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                time(c.name, { sink &+= pt.query(p.getEnvelopeInternal()).sorted().count }, { sink &+= gt.query(g).count })
            case "STRtree.nearest":
                guard let (pt, gt, items) = trees[n[0]] else { continue }
                let p = inputs.port(c.geometries[0]), g = inputs.geos(c.geometries[0])
                time(c.name, { sink &+= pt.nearestNeighbour(p.getEnvelopeInternal(), -1) { i, _ in items[i].distance(p) } ?? 0 },
                     { sink &+= gt.nearest(g) ?? 0 })
            default:
                Issue.record("not timed: \(c.name)")
            }
        }
        var total = Timing()
        print("speed \(name): function, calls, port ms, GEOS ms, port / GEOS (sink \(sink))")
        for (k, t) in timings.sorted(by: { $0.value.port > $1.value.port }) {
            total.calls += t.calls
            total.port += t.port
            total.geos += t.geos
            print(String(format: "speed | %@ | %d | %.1f | %.1f | %.2f |", k, t.calls, SpeedTests.ms(t.port), SpeedTests.ms(t.geos), SpeedTests.ms(t.port) / max(SpeedTests.ms(t.geos), 1e-9)))
        }
        print(String(format: "speed | total | %d | %.1f | %.1f | %.2f |", total.calls, SpeedTests.ms(total.port), SpeedTests.ms(total.geos), SpeedTests.ms(total.port) / SpeedTests.ms(total.geos)))
    }
}
