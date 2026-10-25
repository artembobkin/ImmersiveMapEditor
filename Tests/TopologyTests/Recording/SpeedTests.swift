import Foundation
import Testing
import Topology

/// The time of every recorded call of one whole tile on the port, function
/// by function and in total, against GEOS's times on this machine as they
/// were stored when GEOS left the package (Docs/PortingGoal.md,
/// "Performance": a tile at most 1.5 times GEOS's time). Each call is timed
/// alone, its result made and freed inside the measure. Run with
/// `TOPOLOGY_SPEED=1` in an optimized build
/// (`swift test -c release -Xswiftc -enable-testing --filter SpeedTests`);
/// `TOPOLOGY_SPEED_RECORDING` names the recording (`tiles/19808_10243`).
/// GEOS's times are `expected/<recording>/SpeedTests.geos.tape` beside the
/// recordings, written by GEOS's own run of this test before phase 12.
@Suite(.enabled(if: Recording.available && ProcessInfo.processInfo.environment["TOPOLOGY_SPEED"] == "1"))
struct SpeedTests {
    struct Timing {
        var calls = 0
        var port = Duration.zero
    }

    static func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

    /// GEOS's stored times of a recording, by function: calls and milliseconds.
    static func geosTimes(_ recording: String) -> [String: (calls: Int, ms: Double)] {
        guard let t = try? TapeReader(url: TapeStore.recording(recording).url("SpeedTests.geos")) else { return [:] }
        var out: [String: (Int, Double)] = [:]
        guard let n = (try? t.int()) ?? nil else { return [:] }
        for _ in 0..<n {
            guard let name = (try? t.string()) ?? nil, let calls = (try? t.int()) ?? nil, let ms = (try? t.double()) ?? nil else { break }
            out[name] = (calls, ms)
        }
        return out
    }

    @Test func tile() throws {
        let name = ProcessInfo.processInfo.environment["TOPOLOGY_SPEED_RECORDING"] ?? "tiles/19808_10243"
        guard let file = Recording.files().first(where: { $0.name == name }) else { Issue.record("no recording \(name)"); return }
        let r = try Recording(url: file.url, name: name)
        let inputs = ReplayTests.Inputs(r)
        // Every geometry read first, so reading is not timed.
        for id in r.geometries.keys { _ = inputs.port(id) }
        let clock = ContinuousClock()
        var timings: [String: Timing] = [:]
        var prepared: [Double: PreparedGeometry] = [:]
        var trees: [Double: (STRtree<Int>, [Topology.Geometry])] = [:]
        var sink = 0
        func time(_ name: String, _ port: () -> Void) {
            var t = timings[name] ?? Timing()
            t.calls += 1
            t.port += clock.measure(port)
            timings[name] = t
        }
        func unary(_ c: Recording.Call, _ mine: (Topology.Geometry) throws -> Topology.Geometry) {
            let p = inputs.port(c.geometries[0])
            time(c.name) { if let m = try? mine(p) { sink &+= m.getNumPoints() } }
        }
        func binary(_ c: Recording.Call, _ mine: (Topology.Geometry, Topology.Geometry) throws -> Topology.Geometry) {
            let p = c.geometries.map { inputs.port($0) }
            time(c.name) { if let m = try? mine(p[0], p[1]) { sink &+= m.getNumPoints() } }
        }
        func predicate(_ c: Recording.Call, _ mine: (Topology.Geometry, Topology.Geometry) throws -> Bool) {
            let p = c.geometries.map { inputs.port($0) }
            time(c.name) { if (try? mine(p[0], p[1])) == true { sink &+= 1 } }
        }
        // `TOPOLOGY_SPEED_ONLY` times one function alone (for a profiler), `TOPOLOGY_SPEED_REPEAT` times.
        let only = ProcessInfo.processInfo.environment["TOPOLOGY_SPEED_ONLY"]
        let repeats = Int(ProcessInfo.processInfo.environment["TOPOLOGY_SPEED_REPEAT"] ?? "1") ?? 1
        for _ in 0..<repeats {
        for c in r.calls where only == nil || c.name == only || c.name.hasSuffix(".init") {
            let n = c.numbers
            switch c.name {
            case "intersects": predicate(c) { try $0.intersects($1) }
            case "contains": predicate(c) { try $0.contains($1) }
            case "within": predicate(c) { try $0.within($1) }
            case "intersection": binary(c) { try $0.intersection($1) }
            case "difference": binary(c) { try $0.difference($1) }
            case "union": binary(c) { try $0.union($1) }
            case "unaryUnion":
                guard let p = OverlayReplayTests.collection(c.geometries.map { inputs.port($0) }, .default) else { continue }
                time(c.name) { if let m = try? p.union() { sink &+= m.getNumPoints() } }
            case "buffer": unary(c) { try $0.buffer(n[0], quadSegs: Int(n[1]), endCapStyle: Int(n[2]), joinStyle: Int(n[3]), mitreLimit: n[4]) }
            case "offsetCurve": unary(c) { try $0.offsetCurve(n[0], quadSegs: Int(n[1]), joinStyle: Int(n[2]), mitreLimit: n[3]) }
            case "makeValid": unary(c) { try $0.makeValid() }
            case "setPrecision": unary(c) { try $0.setPrecision(n[0]) }
            case "simplify": unary(c) { try $0.topologyPreserveSimplify(n[0]) }
            case "lineMerge": unary(c) { try $0.lineMerge() }
            case "constrainedDelaunay": unary(c) { try ConstrainedDelaunayTriangulator.triangulate($0) }
            case "centroid": unary(c) { $0.getCentroid() }
            case "representativePoint": unary(c) { $0.getInteriorPoint() }
            case "convexHull": unary(c) { $0.convexHull() }
            case "boundary": unary(c) { $0.getBoundary() }
            case "envelope": unary(c) { $0.getEnvelope() }
            case "minimumRotatedRectangle": unary(c) { MinimumAreaRectangle.getMinimumRectangle($0) }
            case "interpolate": unary(c) { try $0.interpolate(n[0], normalized: n[1] != 0) }
            case "polygonize":
                let p = c.geometries.map { inputs.port($0) }
                time(c.name) { if let m = try? Topology.Geometry.polygonize(p) { sink &+= m.getNumPoints() } }
            case "isValid":
                let p = inputs.port(c.geometries[0])
                time(c.name) { if (try? p.isValid()) == true { sink &+= 1 } }
            case "area":
                let p = inputs.port(c.geometries[0])
                time(c.name) { sink &+= Int(p.getArea().bitPattern & 1) }
            case "length":
                let p = inputs.port(c.geometries[0])
                time(c.name) { sink &+= Int(p.getLength().bitPattern & 1) }
            case "bounds":
                let p = inputs.port(c.geometries[0])
                time(c.name) { sink &+= Int(p.getEnvelopeInternal().minX.bitPattern & 1) }
            case "distance":
                let p = c.geometries.map { inputs.port($0) }
                time(c.name) { sink &+= Int(p[0].distance(p[1]).bitPattern & 1) }
            case "nearestPoints":
                let p = c.geometries.map { inputs.port($0) }
                time(c.name) { sink &+= DistanceOp.nearestPoints(p[0], p[1])?.count ?? 0 }
            case "project":
                let p = c.geometries.map { inputs.port($0) }
                time(c.name) { sink &+= Int(((try? p[0].project(p[1])) ?? 0).bitPattern & 1) }
            case "Prepared.init":
                let p = inputs.port(c.geometries[0])
                var port: PreparedGeometry?
                time(c.name) { port = PreparedGeometryFactory.prepare(p) }
                prepared[n[0]] = port!
            case "Prepared.contains", "Prepared.intersects":
                guard let pp = prepared[n[0]] else { continue }
                let p = inputs.port(c.geometries[0])
                let isContains = c.name == "Prepared.contains"
                time(c.name) { if (try? (isContains ? pp.contains(p) : pp.intersects(p))) == true { sink &+= 1 } }
            case "STRtree.init":
                let ps = c.geometries.map { inputs.port($0) }
                var port: STRtree<Int>?
                time(c.name) {
                    let t = STRtree<Int>(nodeCapacity: 10, tieOrder: .geos)
                    for (i, g) in ps.enumerated() { t.insert(g.getEnvelopeInternal(), i) }
                    port = t
                }
                trees[n[0]] = (port!, ps)
            case "STRtree.query":
                guard let (pt, _) = trees[n[0]] else { continue }
                let p = inputs.port(c.geometries[0])
                time(c.name) { sink &+= pt.query(p.getEnvelopeInternal()).sorted().count }
            case "STRtree.nearest":
                guard let (pt, items) = trees[n[0]] else { continue }
                let p = inputs.port(c.geometries[0])
                time(c.name) { sink &+= pt.nearestNeighbour(p.getEnvelopeInternal(), -1) { i, _ in items[i].distance(p) } ?? 0 }
            default:
                Issue.record("not timed: \(c.name)")
            }
        }
        }
        let geos = SpeedTests.geosTimes(name)
        if geos.isEmpty { print("speed \(name): no stored GEOS times (expected/\(name)/SpeedTests.geos.tape), the port alone") }
        var total = (calls: 0, port: 0.0, geos: 0.0)
        print("speed \(name): function, calls, port ms, GEOS ms (stored), port / GEOS (sink \(sink))")
        for (k, t) in timings.sorted(by: { $0.value.port > $1.value.port }) {
            let p = SpeedTests.ms(t.port), g = geos[k]?.ms ?? .nan
            total.calls += t.calls
            total.port += p
            total.geos += geos[k]?.ms ?? 0
            print(String(format: "speed | %@ | %d | %.1f | %.1f | %.2f |", k, t.calls, p, g, p / max(g, 1e-9)))
        }
        print(String(format: "speed | total | %d | %.1f | %.1f | %.2f |", total.calls, total.port, total.geos, total.port / total.geos))
    }
}
