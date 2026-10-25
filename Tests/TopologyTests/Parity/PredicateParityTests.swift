import Foundation
import Testing
import Topology
import geos

/// The predicates against GEOS 3.13, on seeded random pairs that meet and
/// near-degenerate ones (`OverlayParityTests.partner`), points against
/// polygons, and the prepared forms: every answer equal, and the full
/// intersection matrix (`GEOSRelate`) equal as text.
@Suite struct PredicateParityTests {
    typealias Pred = (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> Int8

    static let predicates: [(String, (Topology.Geometry, Topology.Geometry) throws -> Bool, Pred)] = [
        ("intersects", { try $0.intersects($1) }, GEOSIntersects_r),
        ("contains", { try $0.contains($1) }, GEOSContains_r),
        ("within", { try $0.within($1) }, GEOSWithin_r),
        ("covers", { try $0.covers($1) }, GEOSCovers_r),
        ("coveredBy", { try $0.coveredBy($1) }, GEOSCoveredBy_r),
        ("touches", { try $0.touches($1) }, GEOSTouches_r),
        ("crosses", { try $0.crosses($1) }, GEOSCrosses_r),
        ("overlaps", { try $0.overlaps($1) }, GEOSOverlaps_r),
        ("disjoint", { try $0.disjoint($1) }, GEOSDisjoint_r),
        ("equalsTopo", { try $0.equalsTopo($1) }, GEOSEquals_r),
    ]

    /// Pairs: a random geometry and one meeting it, or a point in or near it.
    static func pairs(_ seed: UInt64, _ count: Int) -> [(Shape, Shape)] {
        var r = RandomGeometries(seed: seed)
        var out: [(Shape, Shape)] = []
        for _ in 0..<count {
            let a = r.geometry()
            if r.chance(0.25), let (cx, cy, size) = OverlayParityTests.frame(a) {
                // A point near the geometry, now and then one of its vertices.
                if r.chance(0.3), !a.isEmpty {
                    var all: [Double] = []
                    func walk(_ s: Shape) { all.append(contentsOf: s.coordinates); s.parts.forEach(walk) }
                    walk(a)
                    let i = r.int(0...(all.count / 2 - 1)) * 2
                    out.append((a, Shape(kind: .point, coordinates: [all[i], all[i + 1]])))
                } else {
                    out.append((a, Shape(kind: .point, coordinates: [cx + size * r.double(-0.6...0.6), cy + size * r.double(-0.6...0.6)])))
                }
                continue
            }
            out.append((a, OverlayParityTests.partner(a, &r)))
        }
        return out
    }

    @Test(arguments: 0..<10) func predicate(_ index: Int) {
        let (name, mine, theirs) = PredicateParityTests.predicates[index]
        let o = GEOSOracle()
        var tally = ParityTally(name)
        var failingBoth = 0
        for (a, b) in PredicateParityTests.pairs(500 + UInt64(index), 4000) {
            for (x, y) in [(a, b), (b, a)] {
                let gx = o.geometry(x)!, gy = o.geometry(y)!
                let m = try? mine(x.topology(), y.topology())
                guard let g = gx.predicate(gy, theirs) else {
                    _ = o.takeError()
                    failingBoth += 1
                    tally.check(m == nil, "\(x) \(name) \(y): GEOS fails, the port gives \(String(describing: m))")
                    continue
                }
                tally.check(m == g, "\(x) \(name) \(y): port \(String(describing: m)) GEOS \(g)")
            }
        }
        tally.report()
        print("parity \(name): GEOS and the port failing alike on \(failingBoth)")
    }

    @Test func relateMatrix() {
        let o = GEOSOracle()
        var tally = ParityTally("relate (GEOSRelate)")
        var geosFails: [String: Int] = [:]
        defer { for (m, n) in geosFails { print("parity relate: GEOS fails \(n) times: \(m.prefix(120))") } }
        for (a, b) in PredicateParityTests.pairs(520, 4000) {
            let ga = o.geometry(a)!, gb = o.geometry(b)!
            let m = (try? a.topology().relate(b.topology()))?.description
            guard let s = GEOSRelate_r(o.handle, ga.ptr, gb.ptr) else {
                let message = o.takeError() ?? ""
                geosFails[message, default: 0] += 1
                tally.check(m == nil, "\(a) relate \(b): GEOS fails (\(message)), the port gives \(String(describing: m))")
                continue
            }
            let g = String(cString: s)
            GEOSFree_r(o.handle, s)
            tally.check(m == g, "\(a) relate \(b): port \(String(describing: m)) GEOS \(g)")
        }
        tally.report()
    }

    static let prepared: [(String, (PreparedGeometry, Topology.Geometry) throws -> Bool,
                           (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> Int8)] = [
        ("Prepared.contains", { try $0.contains($1) }, GEOSPreparedContains_r),
        ("Prepared.intersects", { try $0.intersects($1) }, GEOSPreparedIntersects_r),
        ("Prepared.covers", { try $0.covers($1) }, GEOSPreparedCovers_r),
        ("Prepared.within", { try $0.within($1) }, GEOSPreparedWithin_r),
    ]

    @Test(arguments: 0..<4) func preparedPredicate(_ index: Int) {
        let (name, mine, theirs) = PredicateParityTests.prepared[index]
        let o = GEOSOracle()
        var tally = ParityTally(name)
        for (a, b) in PredicateParityTests.pairs(530 + UInt64(index), 4000) {
            let ga = o.geometry(a)!, gb = o.geometry(b)!
            let pg = ga.prepared()
            let pm = PreparedGeometryFactory.prepare(a.topology())
            let m = try? mine(pm, b.topology())
            guard let g = pg.predicate(gb, theirs) else {
                _ = o.takeError()
                tally.check(m == nil, "\(a) \(name) \(b): GEOS fails, the port gives \(String(describing: m))")
                continue
            }
            tally.check(m == g, "\(a) \(name) \(b): port \(String(describing: m)) GEOS \(g)")
        }
        tally.report()
    }
}
