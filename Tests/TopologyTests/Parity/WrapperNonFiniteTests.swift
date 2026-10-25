import Foundation
import Testing
@testable import Geometry

/// Non-finite coordinates through the new wrapper against the old one's
/// stored results (Docs/PortingTopologyProgress.md, Decisions: GEOS throws
/// where its orientation test meets a NaN or infinite coordinate, and its C
/// API turns that into the function's failure value). No recorded call has
/// one, but the build's geometry is computed (a zero length normalized, a
/// projection of a far point) and could make one. Random polygons, lines and
/// points with a NaN or an infinity put in now and then, built through the
/// public constructors, and every operation of the API on them, compared as
/// the replay compares (`WrapperReplayTests`). In the suite of the replay.
extension WrapperReplayTests {
    /// A random geometry as plain values, to build on either side.
    indirect enum Spec: CustomStringConvertible {
        case point(SIMD2<Double>)
        case line([SIMD2<Double>])
        case polygon([SIMD2<Double>], [[SIMD2<Double>]])
        case multi([Spec])

        func make<G: WrapperGeometry>(_: G.Type) -> G {
            switch self {
            case .point(let p): return G.makePoint(p)
            case .line(let ps): return G.makeLineString(ps)
            case .polygon(let s, let h): return G.makePolygon(s, holes: h)
            case .multi(let m): return G.makeCollection(m.map { $0.make(G.self) })
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

        var description: String {
            switch self {
            case .point(let p): return "point(\(p))"
            case .line(let ps): return "line(\(ps))"
            case .polygon(let s, let h): return "polygon(\(s), \(h))"
            case .multi(let m): return "multi(\(m))"
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

    /// The 2,000 pairs on one wrapper.
    static func nonFiniteWalk<G: WrapperGeometry>(_: G.Type, _ x: ReplayObserver) {
        var r = NonFiniteGenerator(rng: SeededRandom(seed: 8008))
        for k in 0..<2000 {
            let sa = r.spec(poisoned: r.chance(0.8)), sb = r.spec(poisoned: r.chance(0.3))
            let a = sa.make(G.self), b = sb.make(G.self)
            let what = "#\(k) \(sa) | \(sb)"
            WrapperReplayTests.reading(x, what, a)
            x.same("isValid", what, a.isValid)
            x.same("area, length", what, [a.area, a.length].map(bits))
            let ba = a.bounds
            x.same("bounds", what, [ba.0, ba.1, ba.2, ba.3].map(bits))
            x.same("description", what, a.description)
            x.geometry("centroid", what) { a.centroid }
            x.geometry("representativePoint", what) { a.representativePoint }
            x.geometry("convexHull", what) { a.convexHull }
            x.geometry("envelope", what) { a.envelope }
            x.geometry("boundary", what) { a.boundary }
            // GEOS reads before the hull ring for some non-finite hulls (no
            // rectangle is smaller than the largest double): finite input only.
            if sa.isFinite { x.geometry("minimumRotatedRectangle", what) { a.minimumRotatedRectangle } }
            x.geometry("buffer", what) { a.styledBuffer(2, quadSegs: 8, cap: 1, join: 1, mitreLimit: 5) }
            x.geometry("buffer flat mitre", what) { a.styledBuffer(-1, quadSegs: 16, cap: 2, join: 2, mitreLimit: 5) }
            x.geometry("buffer square bevel", what) { a.styledBuffer(0.5, quadSegs: 16, cap: 3, join: 3, mitreLimit: 5) }
            x.geometry("union", what) { a.union(b) }
            x.geometry("intersection", what) { a.intersection(b) }
            x.geometry("difference", what) { a.difference(b) }
            x.geometry("unaryUnion", what) { G.makeUnaryUnion([a, b]) }
            x.geometry("simplify", what) { a.simplify(0.5) }
            x.geometry("makeValid", what) { a.makeValid() }
            x.geometry("setPrecision", what) { a.setPrecision(0.01) }
            x.geometry("offsetCurve", what) { a.styledOffsetCurve(1.5, quadSegs: 16, join: 1, mitreLimit: 5) }
            x.same("distance", what, bits(a.distance(b)))
            x.same("predicates", what, [a.intersects(b), a.contains(b), a.within(b)])
            let p = a.nearestPoints(b)
            x.same("nearestPoints", what, bits(p.0) + bits(p.1))
            if sa.isLinear {
                x.geometry("interpolate", what) { a.interpolate(3, normalized: false) }
                x.geometry("interpolate normalized", what) { a.interpolate(0.4, normalized: true) }
                if case .point = sb { x.same("project", what, bits(a.project(b))) }
                x.geometry("lineMerge", what) { a.lineMerge() }
                // GEOS crashes polygonizing some non-finite lines (a null ring in
                // `EdgeRing::computeValid`): compared on finite lines only.
                if sa.isFinite && sb.isFinite { x.geometry("polygonize", what) { G.makePolygonize([a, b]) } }
            }
            // GEOS's triangulator needs valid polygons (it crashes on some
            // others): the old wrapper's validity decides.
            if case .polygon = sa, x.steer(a.isValid) {
                let t = a.constrainedDelaunay()
                x.same("constrainedDelaunay", what, t.flatMap { bits($0) })
            }
            let pa = G.PreparedType(a)
            x.same("Prepared", what, [pa.contains(b), pa.intersects(b)])
            let tree = G.TreeType([a, b, a])
            x.same("STRtree.query", what, tree.query(b))
            x.same("STRtree.nearest", what, tree.nearest(b))
        }
    }

    @Test func nonFinite() {
        let t = WrapperTallies("wrapper, non-finite coordinates")
        let x = Observers.make("WrapperReplayTests.nonFinite", .fixtures, t)
        if Oracles.freezing { liveNonFinite(x) } else { WrapperReplayTests.nonFiniteWalk(Geometry.self, x) }
        x.finish(sourceLocation: #_sourceLocation)
        t.report()
    }
}
