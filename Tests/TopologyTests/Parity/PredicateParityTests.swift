import Foundation
import Testing
import Topology

/// The predicates against GEOS 3.13's stored answers, on seeded random pairs
/// that meet and near-degenerate ones (`OverlayParityTests.partner`), points
/// against polygons, and the prepared forms: every answer equal, and the
/// full intersection matrix (`GEOSRelate`) equal as text.
@Suite struct PredicateParityTests {
    static let predicates: [(String, (Topology.Geometry, Topology.Geometry) throws -> Bool, PredicateOp)] = [
        ("intersects", { try $0.intersects($1) }, .intersects),
        ("contains", { try $0.contains($1) }, .contains),
        ("within", { try $0.within($1) }, .within),
        ("covers", { try $0.covers($1) }, .covers),
        ("coveredBy", { try $0.coveredBy($1) }, .coveredBy),
        ("touches", { try $0.touches($1) }, .touches),
        ("crosses", { try $0.crosses($1) }, .crosses),
        ("overlaps", { try $0.overlaps($1) }, .overlaps),
        ("disjoint", { try $0.disjoint($1) }, .disjoint),
        ("equalsTopo", { try $0.equalsTopo($1) }, .equalsTopo),
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
        let o = Oracles.make("PredicateParityTests.predicate.\(index)")
        defer { o.finish() }
        var tally = ParityTally(name)
        var failingBoth = 0
        for (a, b) in PredicateParityTests.pairs(500 + UInt64(index), 4000) {
            for (x, y) in [(a, b), (b, a)] {
                let m = try? mine(x.topology(), y.topology())
                guard let g = o.predicate(theirs, [.shape(x), .shape(y)]) else {
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
        let o = Oracles.make("PredicateParityTests.relateMatrix")
        defer { o.finish() }
        var tally = ParityTally("relate (GEOSRelate)")
        var geosFails: [String: Int] = [:]
        defer { for (m, n) in geosFails { print("parity relate: GEOS fails \(n) times: \(m.prefix(120))") } }
        for (a, b) in PredicateParityTests.pairs(520, 4000) {
            let m = (try? a.topology().relate(b.topology()))?.description
            switch o.relate(.shape(a), .shape(b)) {
            case .failure(let f):
                let message = f.message ?? ""
                geosFails[message, default: 0] += 1
                tally.check(m == nil, "\(a) relate \(b): GEOS fails (\(message)), the port gives \(String(describing: m))")
            case .success(let g):
                tally.check(m == g, "\(a) relate \(b): port \(String(describing: m)) GEOS \(g)")
            }
        }
        tally.report()
    }

    static let prepared: [(String, (PreparedGeometry, Topology.Geometry) throws -> Bool, PredicateOp)] = [
        ("Prepared.contains", { try $0.contains($1) }, .contains),
        ("Prepared.intersects", { try $0.intersects($1) }, .intersects),
        ("Prepared.covers", { try $0.covers($1) }, .covers),
        ("Prepared.within", { try $0.within($1) }, .within),
    ]

    @Test(arguments: 0..<4) func preparedPredicate(_ index: Int) {
        let (name, mine, theirs) = PredicateParityTests.prepared[index]
        let o = Oracles.make("PredicateParityTests.preparedPredicate.\(index)")
        defer { o.finish() }
        var tally = ParityTally(name)
        for (a, b) in PredicateParityTests.pairs(530 + UInt64(index), 4000) {
            let pg = o.prepare(.shape(a))
            let pm = PreparedGeometryFactory.prepare(a.topology())
            let m = try? mine(pm, b.topology())
            guard let g = o.prepared(theirs, pg, .shape(b)) else {
                tally.check(m == nil, "\(a) \(name) \(b): GEOS fails, the port gives \(String(describing: m))")
                continue
            }
            tally.check(m == g, "\(a) \(name) \(b): port \(String(describing: m)) GEOS \(g)")
        }
        tally.report()
    }
}
