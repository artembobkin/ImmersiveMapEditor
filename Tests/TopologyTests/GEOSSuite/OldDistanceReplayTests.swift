import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// The recorded `distance` and `nearestPoints` calls of `Geometry` replayed
/// on the port and on GEOS: every value bit for bit. Long: run with
/// `TOPOLOGY_LONG_REPLAY=1`.
@Suite(.enabled(if: Recording.longReplay, "long replays run with TOPOLOGY_LONG_REPLAY=1 and the recordings in .build/recording"))
struct DistanceReplayTests {
    @Test func distance() {
        ReplayTests.replay("distance") { inputs, c, tally in
            let m = inputs.port(c.geometries[0]).distance(inputs.port(c.geometries[1]))
            let g = inputs.geos(c.geometries[0]).measure(inputs.geos(c.geometries[1]), GEOSDistance_r)
            tally.check(m.bitPattern == g?.bitPattern, "#\(c.geometries): port \(m) GEOS \(String(describing: g))")
        }.report()
    }

    @Test func nearestPoints() {
        ReplayTests.replay("nearestPoints") { inputs, c, tally in
            let ga = inputs.geos(c.geometries[0]), gb = inputs.geos(c.geometries[1])
            var theirs: [Double]?
            if let seq = GEOSNearestPoints_r(ga.handle, ga.ptr, gb.ptr) {
                var flat = [Double](repeating: 0, count: 4)
                GEOSCoordSeq_copyToBuffer_r(ga.handle, seq, &flat, 0, 0)
                GEOSCoordSeq_destroy_r(ga.handle, seq)
                theirs = flat
            }
            let mine = DistanceOp.nearestPoints(inputs.port(c.geometries[0]), inputs.port(c.geometries[1])).map { $0.flatMap { [$0.x, $0.y] } }
            tally.check(mine?.map(\.bitPattern) == theirs?.map(\.bitPattern), "#\(c.geometries)")
        }.report()
    }
}
}
