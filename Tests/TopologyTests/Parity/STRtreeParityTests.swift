import Foundation
import Testing
import Topology

/// The STR tree against GEOS's stored answers (`GEOSSTRtree_*`, node capacity
/// 10, as `Geometry`'s `STRtree` made it): the same items found by a query,
/// and the same item nearest, ties included. GEOS's nearest item was found
/// by its own distance (`GEOSDistance`), the port's by its own (equal since
/// phase 4).
@Suite struct STRtreeParityTests {
    /// The port's tree over the same geometries, by index.
    static func portTree(_ shapes: [Shape]) -> STRtree<Int> {
        let t = STRtree<Int>(nodeCapacity: 10, tieOrder: .geos)
        for (i, s) in shapes.enumerated() { t.insert(s.topology().getEnvelopeInternal(), i) }
        return t
    }

    /// Sets of geometries: random, clustered, on a grid (equal distances),
    /// with duplicates.
    static func itemSets(seed: UInt64, count: Int) -> [[Shape]] {
        var r = RandomGeometries(seed: seed)
        return (0..<count).map { _ in
            let n = [0, 1, 5, 11, 50, 120, 400, 1500].randomElement(using: &r.rng)!
            switch r.int(0...2) {
            case 0: return (0..<n).map { _ in r.geometry() }
            case 1:
                let step = [1.0, 0.5, 10.0].randomElement(using: &r.rng)!
                return (0..<n).map { i in Shape(kind: .point, coordinates: [Double(i % 17) * step, Double(i / 17) * step]) }
            default:
                var base = (0..<(n == 0 ? 0 : max(1, n / 3))).map { _ in r.point() }
                base += base.prefix(n - base.count)
                return base.shuffled(using: &r.rng)
            }
        }
    }

    /// A stored list of indices as text, when kept whole.
    static func describe(_ s: StoredBytes) -> String {
        s.whole.map { "\(TapeReader.decode($0).count) items" } ?? "a digest"
    }

    @Test func queryAndNearest() {
        let o = Oracles.make("STRtreeParityTests.queryAndNearest")
        defer { o.finish() }
        var query = ParityTally("STRtree.query")
        var nearest = ParityTally("STRtree.nearest (ties included)")
        var r = RandomGeometries(seed: 50)
        for shapes in STRtreeParityTests.itemSets(seed: 51, count: 300) {
            let geos = o.tree(shapes.map { .shape($0) })
            let port = STRtreeParityTests.portTree(shapes)
            for _ in 0..<20 {
                let q = r.chance(0.3) && !shapes.isEmpty ? shapes.randomElement(using: &r.rng)! : r.geometry()
                let mine = port.query(q.topology().getEnvelopeInternal()).sorted()
                let theirs = o.query(geos, .shape(q))
                query.check(theirs.matches(TapeReader.encode(mine)),
                            "\(shapes.count) items, query \(q): \(mine.count) vs \(STRtreeParityTests.describe(theirs))")
                if q.isEmpty { continue }
                // The port's own distance (phase 4) on the port's side.
                let items = shapes.map { $0.topology() }, qt = q.topology()
                let n = port.nearestNeighbour(qt.getEnvelopeInternal(), -1) { i, _ in items[i].distance(qt) }
                let g = o.nearest(geos, .shape(q))
                nearest.check(n == g, "\(shapes.count) items, \(q): \(String(describing: n)) vs \(String(describing: g))")
            }
        }
        query.report()
        nearest.report()
    }
}
