import Foundation
import Testing
import Topology

/// The noder against GEOS's stored answers of `GEOSNode`, which nodes the
/// lines of a geometry (rings included) with an iterated MC index noder at
/// floating precision and drops the duplicate substrings (in either
/// direction), keeping the first: the port's `IteratedNoder` and
/// `OrientedCoordinateArray` doing the same give the same lines, in the same
/// order, bit for bit. An empty input comes back as it is. GEOS crashes (a
/// segmentation fault) on a collection that holds an empty geometry, so
/// those inputs are counted and were not given to it.
///
/// Bit for bit includes the sign of a zero: at a zero-length segment between
/// `0.0` and `-0.0`, which of the two equal values a node takes follows the
/// order GEOS meets the pairs of chains in (`STRtree.queryPairs`) and keeps
/// its nodes in (`SegmentNodeList`). The two inputs that showed it in phase 3
/// are checked by name.
@Suite struct NodingParityTests {
    /// The lines of a geometry, rings included, in order.
    static func lines(_ g: Topology.Geometry) -> [[Coordinate]] {
        var out: [[Coordinate]] = []
        g.applyComponents { c in
            if let l = c as? LineString, !l.isEmpty() { out.append(l.points) }
        }
        return out
    }

    /// Whether a collection holds an empty geometry, at any depth.
    static func hasEmptyPart(_ s: Shape) -> Bool {
        s.parts.contains { $0.isEmpty || ($0.kind.rawValue >= 4 && hasEmptyPart($0)) }
    }

    /// `GEOSNode` done by the port.
    static func node(_ g: Topology.Geometry) throws -> Topology.Geometry {
        if g.isEmpty() { return g.copy() }
        let strings: [SegmentString] = lines(g).map { NodedSegmentString($0, nil) }
        let noder = IteratedNoder(.floating)
        try noder.computeNodes(strings)
        var kept: [OrientedCoordinateArray] = []
        var out: [LineString] = []
        for s in noder.getNodedSubstrings() {
            let oca = OrientedCoordinateArray(s.getCoordinates())
            if kept.contains(where: { $0.compareTo(oca) == 0 }) { continue }
            kept.append(oca)
            out.append(g.factory.createLineString(s.getCoordinates()))
        }
        return g.factory.createMultiLineString(out)
    }

    static func compare(_ s: Shape, _ o: StoredOracle, _ tally: inout ParityTally) {
        let g = s.topology()
        guard case .result(let expected) = o.geometry(.node, [.shape(s)]) else {
            let mine = try? NodingParityTests.node(g)
            tally.check(mine == nil, "\(s): GEOS fails, the port does not")
            return
        }
        guard let mine = try? NodingParityTests.node(g) else {
            tally.check(false, "\(s): the port fails")
            return
        }
        tally.check(expected.rawEquals(Shape(mine)), "\(s):\n  port \(Shape(mine))\n  GEOS \(expected.description)")
    }

    @Test func nodeLikeGEOSNode() {
        let o = Oracles.make("NodingParityTests.nodeLikeGEOSNode")
        defer { o.finish() }
        var tally = ParityTally("MCIndexNoder, IteratedNoder (GEOSNode)")
        var r = RandomGeometries(seed: 60)
        var crashing = 0
        for _ in 0..<5000 {
            var s = r.geometry()
            if r.chance(0.3) { s = Shape(kind: .geometryCollection, parts: [s, r.lineString(), r.lineString()]) }
            if s.kind.rawValue >= 4 && NodingParityTests.hasEmptyPart(s) {
                crashing += 1
                continue
            }
            NodingParityTests.compare(s, o, &tally)
        }
        tally.report()
        print("parity GEOSNode: \(crashing) inputs with an empty geometry in a collection, which crash GEOS, not compared")
    }

    /// The inputs whose nodes took the other zero in phase 3.
    @Test func theSignOfAZeroAtANode() throws {
        let o = Oracles.make("NodingParityTests.theSignOfAZeroAtANode")
        defer { o.finish() }
        var tally = ParityTally("GEOSNode, the sign of a zero")
        for wkt in ["LINESTRING (1 0, 0 0, -0 0, -1 -1)",
                    "POLYGON ((300 -225, -37.5 37.5, -150 -0, -149.99999999975554 -75, -150 -150, -262.5 -225, -75 -450, -0 -525, 0 -525, 37.5 -487.5, 225 -412.5, 225 -300, 300 -225))"] {
            NodingParityTests.compare(Shape(try WKTReader().read(wkt)), o, &tally)
        }
        tally.report()
        #expect(tally.compared == 2)
    }
}
