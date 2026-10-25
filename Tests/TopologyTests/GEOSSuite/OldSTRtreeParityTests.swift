import Foundation
import Testing
import Topology
import geos

extension GEOSSuite {
/// The STR tree against GEOS's (`GEOSSTRtree_*`, node capacity 10, as
/// `Geometry`'s `STRtree` makes it): the same items found by a query, and
/// the same item nearest, ties included. The distance between items is
/// GEOS's own (`GEOSDistance`) on both sides, so the tree is compared, not
/// the distance (ported in phase 4).
@Suite struct STRtreeParityTests {
    /// GEOS's tree over geometries, the way `Geometry.STRtree` drives it.
    final class GEOSTree {
        let oracle: GEOSOracle
        let tree: OpaquePointer
        let items: [GEOSGeom]
        var index: [OpaquePointer: Int] = [:]

        init(_ o: GEOSOracle, _ items: [GEOSGeom]) {
            oracle = o
            self.items = items
            tree = GEOSSTRtree_create_r(o.handle, 10)
            for (i, g) in items.enumerated() {
                index[g.ptr] = i
                GEOSSTRtree_insert_r(o.handle, tree, g.ptr, UnsafeMutableRawPointer(g.ptr))
            }
        }

        deinit { GEOSSTRtree_destroy_r(oracle.handle, tree) }

        func query(_ g: GEOSGeom) -> [Int] {
            final class Box { var found: [Int] = []; var index: [OpaquePointer: Int] = [:] }
            let box = Box()
            box.index = index
            GEOSSTRtree_query_r(oracle.handle, tree, g.ptr, { item, data in
                let b = Unmanaged<Box>.fromOpaque(data!).takeUnretainedValue()
                if let item, let i = b.index[OpaquePointer(item)] { b.found.append(i) }
            }, Unmanaged.passUnretained(box).toOpaque())
            return box.found.sorted()
        }

        func nearest(_ g: GEOSGeom) -> Int? {
            guard !items.isEmpty, let p = GEOSSTRtree_nearest_r(oracle.handle, tree, g.ptr) else { return nil }
            return index[p]
        }
    }

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

    @Test func queryAndNearest() {
        let o = GEOSOracle()
        var query = ParityTally("STRtree.query")
        var nearest = ParityTally("STRtree.nearest (ties included)")
        var r = RandomGeometries(seed: 50)
        for shapes in STRtreeParityTests.itemSets(seed: 51, count: 300) {
            let geos = GEOSTree(o, shapes.map { o.geometry($0)! })
            let port = STRtreeParityTests.portTree(shapes)
            for _ in 0..<20 {
                let q = r.chance(0.3) && !shapes.isEmpty ? shapes.randomElement(using: &r.rng)! : r.geometry()
                let gq = o.geometry(q)!
                let mine = port.query(q.topology().getEnvelopeInternal()).sorted()
                let theirs = geos.query(gq)
                query.check(mine == theirs, "\(shapes.count) items, query \(q): \(mine.count) vs \(theirs.count)")
                if q.isEmpty { continue }
                // The port's own distance (phase 4) on the port's side.
                let items = shapes.map { $0.topology() }, qt = q.topology()
                let n = port.nearestNeighbour(qt.getEnvelopeInternal(), -1) { i, _ in items[i].distance(qt) }
                let g = geos.nearest(gq)
                nearest.check(n == g, "\(shapes.count) items, \(q): \(String(describing: n)) vs \(String(describing: g))")
            }
        }
        query.report()
        nearest.report()
    }
}
}
