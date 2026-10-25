import Foundation
import Testing
import Topology

/// The recorded overlay calls of `Geometry` replayed on the port against
/// GEOS's stored answers: `intersection`, `difference`, `union` and
/// `unaryUnion` (whose parts the wrapper gathers into one collection, as
/// here). Results in GEOS's normal form bit for bit, and as they come; the
/// port's time is printed (the operation alone, not the conversions). Long:
/// run with `TOPOLOGY_LONG_REPLAY=1`, best in a release build.
@Suite(.enabled(if: Recording.longStored, "long replays run with TOPOLOGY_LONG_REPLAY=1, the recordings and their stored answers in .build/recording"))
struct OverlayReplayTests {
    struct Timed {
        var port = Duration.zero

        func report(_ name: String) {
            func ms(_ d: Duration) -> String { String(format: "%.0f ms", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15) }
            print("timing \(name): port \(ms(port))")
        }
    }

    static func replayBinary(_ name: String, _ mine: (Topology.Geometry, Topology.Geometry) throws -> Topology.Geometry, _ op: GeometryOp) {
        var t = OverlayParityTests.Tallies("replay \(name)")
        var time = Timed()
        let clock = ContinuousClock()
        Recording.replay("OverlayReplayTests.\(name)") { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == name {
                let a = inputs.port(c.geometries[0]), b = inputs.port(c.geometries[1])
                let g = o.geometry(op, [inputs.input(c.geometries[0]), inputs.input(c.geometries[1])])
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure { m = Result { try mine(a, b) } }
                OverlayParityTests.compare("\(r.name) #\(c.geometries)", { try m.get() }, g, &t)
            }
        }
        t.report()
        time.report(name)
    }

    @Test func intersection() { OverlayReplayTests.replayBinary("intersection", { try $0.intersection($1) }, .intersection) }
    @Test func difference() { OverlayReplayTests.replayBinary("difference", { try $0.difference($1) }, .difference) }
    @Test func union() { OverlayReplayTests.replayBinary("union", { try $0.union($1) }, .union) }

    /// The collection `Geometry.collection` makes of the parts: the parts'
    /// members (a part of a multi-geometry or collection taken apart), empty
    /// ones dropped, as a multi-geometry when they are all of one kind.
    static func collection(_ parts: [Topology.Geometry], _ f: GeometryFactory) -> Topology.Geometry? {
        let flat = parts.flatMap { p -> [Topology.Geometry] in
            if p.isEmpty() { return [] }
            if let c = p as? GeometryCollection { return c.geometries }
            return [p]
        }
        if flat.isEmpty { return nil }
        if flat.allSatisfy({ type(of: $0) == Polygon.self }) { return f.createMultiPolygon(flat.map { $0 as! Polygon }) }
        if flat.allSatisfy({ type(of: $0) == LineString.self }) { return f.createMultiLineString(flat.map { $0 as! LineString }) }
        if flat.allSatisfy({ type(of: $0) == Point.self }) { return f.createMultiPoint(flat.map { $0 as! Point }) }
        return f.createGeometryCollection(flat)
    }

    @Test func unaryUnion() {
        var t = OverlayParityTests.Tallies("replay unaryUnion")
        var time = Timed()
        let clock = ContinuousClock()
        Recording.replay("OverlayReplayTests.unaryUnion") { r, o in
            let inputs = ReplayTests.Inputs(r)
            for c in r.calls where c.name == "unaryUnion" {
                guard let coll = OverlayReplayTests.collection(c.geometries.map { inputs.port($0) }, .default) else { continue }
                let g = o.geometry(.unaryUnion, [.shape(Shape(coll))])
                var m: Result<Topology.Geometry, Error>!
                time.port += clock.measure { m = Result { try coll.union() } }
                OverlayParityTests.compare("\(r.name) #\(c.geometries.prefix(5))", { try m.get() }, g, &t)
            }
        }
        t.report()
        time.report("unaryUnion")
    }
}
