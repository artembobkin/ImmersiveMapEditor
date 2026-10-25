import Foundation
import Testing
@testable import Geometry

/// Non-finite coordinates through both wrappers (Docs/PortingTopologyProgress.md,
/// Decisions: GEOS throws where its orientation test meets a NaN or infinite
/// coordinate, and its C API turns that into the function's failure value).
/// No recorded call has one, but the build's geometry is computed (a zero
/// length normalized, a projection of a far point) and could make one. Random
/// polygons, lines and points with a NaN or an infinity put in now and then,
/// built through the public constructors on each side, and every operation of
/// the API on them, compared as the replay compares
/// (`WrapperReplayTests.compare`). In the suite of the replay, which is
/// serialized for the old wrapper's one GEOS context.
extension GEOSSuite.WrapperReplayTests {
    /// A random geometry as plain values, to build on either side.
    indirect enum Spec {
        case point(SIMD2<Double>)
        case line([SIMD2<Double>])
        case polygon([SIMD2<Double>], [[SIMD2<Double>]])
        case multi([Spec])

        func old() -> Old {
            switch self {
            case .point(let p): return .point(p)
            case .line(let ps): return .lineString(ps)
            case .polygon(let s, let h): return .polygon(s, holes: h)
            case .multi(let m): return .collection(m.map { $0.old() })
            }
        }

        func new() -> Geometry {
            switch self {
            case .point(let p): return .point(p)
            case .line(let ps): return .lineString(ps)
            case .polygon(let s, let h): return .polygon(s, holes: h)
            case .multi(let m): return .collection(m.map { $0.new() })
            }
        }

        /// Whether every coordinate is finite.
        var isFinite: Bool {
            func ok(_ p: SIMD2<Double>) -> Bool { p.x.isFinite && p.y.isFinite }
            switch self {
            case .point(let p): return ok(p)
            case .line(let ps): return ps.allSatisfy(ok)
            case .polygon(let s, let h): return s.allSatisfy(ok) && h.allSatisfy { $0.allSatisfy(ok) }
            case .multi(let m): return m.allSatisfy(\.isFinite)
            }
        }

        var isLinear: Bool {
            switch self {
            case .line: return true
            case .multi(let m): return m.allSatisfy(\.isLinear)
            default: return false
            }
        }
    }

    struct NonFiniteGenerator {
        var rng: SeededRandom

        mutating func double(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &rng) }
        mutating func chance(_ p: Double) -> Bool { double(0...1) < p }

        mutating func ring(_ c: SIMD2<Double>, _ radius: Double, _ n: Int) -> [SIMD2<Double>] {
            (0..<n).map { _ in double(0...(2 * .pi)) }.sorted().map { a in c + SIMD2(cos(a), sin(a)) * radius * double(0.5...1) }
        }

        /// One coordinate made NaN or infinite, now and then the first.
        mutating func poison(_ ps: inout [SIMD2<Double>]) {
            guard !ps.isEmpty else { return }
            let i = chance(0.3) ? 0 : Int.random(in: 0..<ps.count, using: &rng)
            let v = [Double.nan, .infinity, -.infinity].randomElement(using: &rng)!
            if chance(0.5) { ps[i].x = v } else { ps[i].y = v }
            if chance(0.15) { ps[i] = SIMD2(.nan, .nan) }
        }

        mutating func spec(poisoned: Bool) -> Spec {
            let c = SIMD2(double(0...100), double(0...100)), r = double(1...20)
            var s: Spec
            switch Int.random(in: 0...9, using: &rng) {
            case 0, 1:
                var p = [c]
                if poisoned { poison(&p) }
                s = .point(p[0])
            case 2, 3, 4:
                var ps = (0..<Int.random(in: 2...8, using: &rng)).map { _ in c + SIMD2(double(-r...r), double(-r...r)) }
                if poisoned { poison(&ps) }
                s = .line(ps)
            case 5:
                s = .multi((0..<2).map { _ in spec(poisoned: poisoned && chance(0.6)) })
            default:
                var shell = ring(c, r, Int.random(in: 3...10, using: &rng))
                var holes = chance(0.3) ? [ring(c, r * 0.3, Int.random(in: 3...6, using: &rng)).reversed()] : [[SIMD2<Double>]]()
                if poisoned {
                    if !holes.isEmpty && chance(0.4) { poison(&holes[0]) } else { poison(&shell) }
                }
                s = .polygon(shell, holes)
            }
            return s
        }
    }

    @Test func nonFinite() {
        let t = Tallies("wrapper, non-finite coordinates")
        var r = NonFiniteGenerator(rng: SeededRandom(seed: 8008))
        for k in 0..<2000 {
            let sa = r.spec(poisoned: r.chance(0.8)), sb = r.spec(poisoned: r.chance(0.3))
            let oa = sa.old(), na = sa.new(), ob = sb.old(), nb = sb.new()
            let what = "#\(k) \(sa) | \(sb)"
            GEOSSuite.WrapperReplayTests.reading(t, what, oa, na)
            let c = GEOSSuite.WrapperReplayTests.self
            c.same(t, "isValid", what, oa.isValid, na.isValid)
            c.same(t, "area, length", what, [oa.area, oa.length].map(c.bits), [na.area, na.length].map(c.bits))
            let ba = oa.bounds, bn = na.bounds
            c.same(t, "bounds", what, [ba.0, ba.1, ba.2, ba.3].map(c.bits), [bn.0, bn.1, bn.2, bn.3].map(c.bits))
            c.same(t, "description", what, oa.description, na.description)
            c.compare(t, "centroid", what, { oa.centroid }, { na.centroid })
            c.compare(t, "representativePoint", what, { oa.representativePoint }, { na.representativePoint })
            c.compare(t, "convexHull", what, { oa.convexHull }, { na.convexHull })
            c.compare(t, "envelope", what, { oa.envelope }, { na.envelope })
            c.compare(t, "boundary", what, { oa.boundary }, { na.boundary })
            // GEOS reads before the hull ring for some non-finite hulls (no
            // rectangle is smaller than the largest double): finite input only.
            if sa.isFinite { c.compare(t, "minimumRotatedRectangle", what, { oa.minimumRotatedRectangle }, { na.minimumRotatedRectangle }) }
            c.compare(t, "buffer", what, { oa.buffer(2, quadSegs: 8) }, { na.buffer(2, quadSegs: 8) })
            c.compare(t, "buffer flat mitre", what, { oa.buffer(-1, cap: .flat, join: .mitre) }, { na.buffer(-1, cap: .flat, join: .mitre) })
            c.compare(t, "buffer square bevel", what, { oa.buffer(0.5, cap: .square, join: .bevel) }, { na.buffer(0.5, cap: .square, join: .bevel) })
            c.compare(t, "union", what, { oa.union(ob) }, { na.union(nb) })
            c.compare(t, "intersection", what, { oa.intersection(ob) }, { na.intersection(nb) })
            c.compare(t, "difference", what, { oa.difference(ob) }, { na.difference(nb) })
            c.compare(t, "unaryUnion", what, { .unaryUnion([oa, ob]) }, { .unaryUnion([na, nb]) })
            c.compare(t, "simplify", what, { oa.simplify(0.5) }, { na.simplify(0.5) })
            c.compare(t, "makeValid", what, { oa.makeValid() }, { na.makeValid() })
            c.compare(t, "setPrecision", what, { oa.setPrecision(0.01) }, { na.setPrecision(0.01) })
            c.compare(t, "offsetCurve", what, { oa.offsetCurve(1.5) }, { na.offsetCurve(1.5) })
            c.same(t, "distance", what, c.bits(oa.distance(ob)), c.bits(na.distance(nb)))
            c.same(t, "predicates", what, [oa.intersects(ob), oa.contains(ob), oa.within(ob)], [na.intersects(nb), na.contains(nb), na.within(nb)])
            let po = oa.nearestPoints(ob), pn = na.nearestPoints(nb)
            c.same(t, "nearestPoints", what, c.bits(po.0) + c.bits(po.1), c.bits(pn.0) + c.bits(pn.1))
            if sa.isLinear {
                c.compare(t, "interpolate", what, { oa.interpolate(3) }, { na.interpolate(3) })
                c.compare(t, "interpolate normalized", what, { oa.interpolate(0.4, normalized: true) }, { na.interpolate(0.4, normalized: true) })
                if case .point = sb { c.same(t, "project", what, c.bits(oa.project(ob)), c.bits(na.project(nb))) }
                c.compare(t, "lineMerge", what, { oa.lineMerge() }, { na.lineMerge() })
                // GEOS crashes polygonizing some non-finite lines (a null ring in
                // `EdgeRing::computeValid`): compared on finite lines only.
                if sa.isFinite && sb.isFinite { c.compare(t, "polygonize", what, { .polygonize([oa, ob]) }, { .polygonize([na, nb]) }) }
            }
            // GEOS's triangulator needs valid polygons (it crashes on some others).
            if case .polygon = sa, oa.isValid {
                let to = oa.constrainedDelaunay(), tn = na.constrainedDelaunay()
                c.same(t, "constrainedDelaunay", what, to.flatMap { c.bits($0) }, tn.flatMap { c.bits($0) })
            }
            let pro = GEOSWrapper.Prepared(oa), prn = Prepared(na)
            c.same(t, "Prepared", what, [pro.contains(ob), pro.intersects(ob)], [prn.contains(nb), prn.intersects(nb)])
            let tro = GEOSWrapper.STRtree([oa, ob, oa]), trn = STRtree([na, nb, na])
            c.same(t, "STRtree.query", what, tro.query(ob), trn.query(nb))
            c.same(t, "STRtree.nearest", what, tro.nearest(ob), trn.nearest(nb))
        }
        t.report()
    }
}
