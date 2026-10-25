import Foundation
import Testing
import Topology

/// The recorded calls of `Geometry` on real data replayed on the port and
/// compared with GEOS's stored answers (outside git, beside the
/// recordings): the same results, bit for bit (geometries in GEOS's normal
/// form).
@Suite(.enabled(if: Recording.stored, "no recordings or no stored answers in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct ReplayTests {
    /// A recording's geometries, read once by the port.
    final class Inputs {
        let recording: Recording
        var port: [UInt32: Topology.Geometry] = [:]

        init(_ r: Recording) { recording = r }

        func port(_ id: UInt32) -> Topology.Geometry {
            if let g = port[id] { return g }
            let g = try! WKBReader().read(recording.geometries[id]!)
            port[id] = g
            return g
        }

        func input(_ id: UInt32) -> OracleInput { recording.input(id) }
    }

    /// Replays every call named `name` in every recording.
    static func replay(_ name: String, _ check: (Inputs, StoredOracle, Recording.Call, inout ParityTally) -> Void) -> ParityTally {
        var tally = ParityTally("replay \(name)")
        Recording.replay("ReplayTests.\(name)") { r, o in
            let inputs = Inputs(r)
            for c in r.calls where c.name == name { check(inputs, o, c, &tally) }
        }
        return tally
    }

    static func unary(_ name: String, _ mine: @escaping (Topology.Geometry) -> Topology.Geometry, _ op: GeometryOp) -> ParityTally {
        replay(name) { inputs, o, c, tally in
            let id = c.geometries[0]
            let m = mine(inputs.port(id))
            guard case .result(let g) = o.geometry(op, [inputs.input(id)]) else { return tally.check(false, "\(name) #\(id): GEOS failed") }
            tally.check(g.compare(raw: Shape(m), normal: Shape(m.norm())) == .equal, "\(name) #\(id): port \(Shape(m.norm())) GEOS \(g.normalDescription)")
        }
    }

    static func measure(_ name: String, _ mine: @escaping (Topology.Geometry) -> Double, _ op: MeasureOp) -> ParityTally {
        replay(name) { inputs, o, c, tally in
            let id = c.geometries[0]
            let m = mine(inputs.port(id)), g = o.measure(op, [inputs.input(id)])
            tally.check(m.bitPattern == g?.bitPattern, "\(name) #\(id): \(m) vs \(String(describing: g))")
        }
    }

    @Test func area() { ReplayTests.measure("area", { $0.getArea() }, .area).report() }
    @Test func length() { ReplayTests.measure("length", { $0.getLength() }, .length).report() }

    @Test func bounds() {
        ReplayTests.replay("bounds") { inputs, o, c, tally in
            let p = inputs.port(c.geometries[0])
            let e = p.getEnvelopeInternal()
            let mine = p.isEmpty() ? [0.0, 0, 0, 0] : [e.minX, e.minY, e.maxX, e.maxY]
            let v = o.bounds(inputs.input(c.geometries[0]))
            tally.check(v.matches(TapeReader.encode(mine)), "#\(c.geometries[0]): \(mine) vs \(v.whole.map(TapeReader.decode(doubles:)) ?? [])")
        }.report()
    }

    @Test func centroid() { ReplayTests.unary("centroid", { $0.getCentroid() }, .centroid).report() }
    @Test func representativePoint() {
        ReplayTests.unary("representativePoint", { $0.getInteriorPoint() }, .pointOnSurface).report()
    }
    @Test func convexHull() { ReplayTests.unary("convexHull", { $0.convexHull() }, .convexHull).report() }
    @Test func boundary() { ReplayTests.unary("boundary", { $0.getBoundary() }, .boundary).report() }
    @Test func minimumRotatedRectangle() {
        ReplayTests.unary("minimumRotatedRectangle", { MinimumAreaRectangle.getMinimumRectangle($0) }, .minimumRotatedRectangle).report()
    }

    /// Every recorded geometry read from its WKB by the port is GEOS's.
    /// Geometries in the order of their ids.
    @Test func wkbReading() {
        var tally = ParityTally("replay WKB reading")
        Recording.replay("ReplayTests.wkbReading") { r, o in
            for id in r.geometries.keys.sorted() {
                let p = try? WKBReader().read(r.geometries[id]!)
                switch (p, o.read(r.input(id))) {
                case (let p?, .result(let g)): tally.check(g.rawEquals(Shape(p)), "\(r.name) #\(id)")
                case (nil, .failure): tally.check(true, "")
                default: tally.check(false, "\(r.name) #\(id)")
                }
            }
        }
        tally.report()
    }
}

/// The recorded trees (`STRtree.init`) rebuilt by the port, their recorded
/// queries and nearest searches replayed against GEOS's stored answers, the
/// nearest item found by each side's own distance (`GEOSDistance`, the
/// port's `distance`).
@Suite(.enabled(if: Recording.stored, "no recordings or no stored answers in .build/recording (see Docs/PortingTopologyProgress.md)"))
struct STRtreeReplayTests {
    @Test func treesQueriesAndNearest() {
        var query = ParityTally("replay STRtree.query")
        var nearest = ParityTally("replay STRtree.nearest")
        Recording.replay("STRtreeReplayTests.treesQueriesAndNearest") { r, o in
            let inputs = ReplayTests.Inputs(r)
            var trees: [Double: (STRtree<Int>, Int, Bool)] = [:]
            var ports: [Double: [Topology.Geometry]] = [:]
            for c in r.calls {
                switch c.name {
                case "STRtree.init":
                    let port = STRtree<Int>(nodeCapacity: 10, tieOrder: .geos)
                    for (i, id) in c.geometries.enumerated() { port.insert(inputs.port(id).getEnvelopeInternal(), i) }
                    trees[c.numbers[0]] = (port, o.tree(c.geometries.map { inputs.input($0) }), c.geometries.isEmpty)
                    ports[c.numbers[0]] = c.geometries.map { inputs.port($0) }
                case "STRtree.query":
                    guard let (port, geos, _) = trees[c.numbers[0]] else { continue }
                    let mine = port.query(inputs.port(c.geometries[0]).getEnvelopeInternal()).sorted()
                    query.check(o.query(geos, inputs.input(c.geometries[0])).matches(TapeReader.encode(mine)), "\(r.name) #\(c.geometries[0])")
                case "STRtree.nearest":
                    guard let (port, geos, empty) = trees[c.numbers[0]] else { continue }
                    let p = inputs.port(c.geometries[0])
                    let items = ports[c.numbers[0]] ?? []
                    let mine = empty ? nil : port.nearestNeighbour(p.getEnvelopeInternal(), -1) { i, _ in items[i].distance(p) }
                    let theirs = o.nearest(geos, inputs.input(c.geometries[0]))
                    nearest.check(mine == theirs, "\(r.name) #\(c.geometries[0]): \(String(describing: mine)) vs \(String(describing: theirs))")
                default: break
                }
            }
        }
        query.report()
        nearest.report()
    }
}
