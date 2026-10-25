import Foundation
import Testing
import Topology

/// The recorded `distance` and `nearestPoints` calls of `Geometry` replayed
/// on the port against GEOS's stored answers: every value bit for bit.
/// Long: run with `TOPOLOGY_LONG_REPLAY=1`.
@Suite(.enabled(if: Recording.longStored, "long replays run with TOPOLOGY_LONG_REPLAY=1, the recordings and their stored answers in .build/recording"))
struct DistanceReplayTests {
    @Test func distance() {
        ReplayTests.replay("distance") { inputs, o, c, tally in
            let m = inputs.port(c.geometries[0]).distance(inputs.port(c.geometries[1]))
            let g = o.measure(.distance, [inputs.input(c.geometries[0]), inputs.input(c.geometries[1])])
            tally.check(m.bitPattern == g?.bitPattern, "#\(c.geometries): port \(m) GEOS \(String(describing: g))")
        }.report()
    }

    @Test func nearestPoints() {
        ReplayTests.replay("nearestPoints") { inputs, o, c, tally in
            let theirs = o.nearestPoints(inputs.input(c.geometries[0]), inputs.input(c.geometries[1]))
            let mine = DistanceOp.nearestPoints(inputs.port(c.geometries[0]), inputs.port(c.geometries[1])).map { $0.flatMap { [$0.x, $0.y] } }
            tally.check(theirs.matches(mine.map { TapeReader.encode($0) }), "#\(c.geometries)")
        }.report()
    }
}
