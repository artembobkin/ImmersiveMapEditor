import Foundation
import Testing
@testable import Geometry

/// Phase 8's proof that the swap changes nothing, frozen: every recorded
/// call of `Geometry` replayed through the new `Geometry` (on `Topology`)
/// and compared with what the old one on GEOS (the wrapper as it stood at
/// commit 50caf95, removed with GEOS) gave, stored beside the recordings: results as they come, bit
/// for bit, geometries by their kind, their WKB (every coordinate's bits,
/// the sign of zeros included) and the grid of the precision model each
/// part carries; numbers by their bits; answers, indices and text exactly.
/// One walk (`replay`) runs on either wrapper (`WrapperGeometry`): on the old
/// one it stored the answers, on the new one it compares with them.
///
/// Each recording is replayed twice: with its geometries as recorded (WKB
/// keeps no precision model, so they are floating), and with every input
/// first put on the grid of 0.01 by `setPrecision` on each side, as the
/// build's `clean` leaves its geometries, which makes the later operations
/// snap-round on that grid as they did in the build.
///
/// GEOS shuffles the vertices it snap-rounds at random (`std::shuffle` from
/// `std::random_device`), so on a fixed grid its own results can change the
/// sign of a zero from run to run (Docs/PortingParity.md, phase 4). A result
/// equal to GEOS's by value but not by bits counts as GEOS's randomness only
/// when GEOS itself gave another result within ten more runs when its
/// answer was stored, and is counted apart; otherwise it is a difference.
/// Serialized, as the old wrapper had one GEOS context.
@Suite(.serialized)
struct WrapperReplayTests {
    static func bits(_ v: Double) -> UInt64 { v.bitPattern }
    static func bits(_ p: P2) -> [UInt64] { [p.x.bitPattern, p.y.bitPattern] }
    static func bits(_ ps: [P2]) -> [UInt64] { ps.flatMap { bits($0) } }

    /// The reading API and the constructors on one geometry, and the
    /// geometries made from what was read.
    static func reading<G: WrapperGeometry>(_ x: ReplayObserver, _ what: String, _ g: G) {
        x.same("kind, isEmpty, isMulti", what, [Int(g.kindCode), g.isEmpty ? 1 : 0, g.isMulti ? 1 : 0])
        x.same("x, y, coords", what, bits(g.xy) + bits(g.coords))
        x.same("exterior, interiors", what, bits(g.exterior) + g.interiors.flatMap { [0] + bits($0) })
        x.same("polygons, lines", what, [g.polygons.count, g.lines.count])
        let parts = g.parts
        x.same("parts", what, parts.map(\.wkb))
        x.same("parts' grids", what, parts.flatMap(\.grids).map(\.bitPattern))
        // The old side's kind steers, as the old test switched on it.
        switch x.steer(Int(g.kindCode)) {
        case 0: x.geometry("point", what) { G.makePoint(g.xy) }
        case 1, 2:
            x.geometry("lineString", what) { G.makeLineString(g.coords) }
            let l = Double(bitPattern: x.steer(g.length.bitPattern))
            x.geometry("substring", what) { g.substring(l * 0.2, l * 0.7) }
        case 3:
            x.geometry("polygon", what) { G.makePolygon(g.exterior, holes: g.interiors) }
            x.geometry("oriented", what) { g.oriented(1) }
            x.geometry("oriented(-1)", what) { g.oriented(-1) }
        default:
            x.geometry("collection", what) { G.makeCollection(g.parts) }
        }
        x.geometry("map", what) { g.map { $0 * 1.5 + SIMD2(3, -7) } }
        x.geometry("rotate", what) { g.rotate(17, origin: SIMD2(3, -4), radians: false) }
        x.geometry("scale", what) { g.scale(1.25, 0.75, origin: SIMD2(-2, 5)) }
        x.geometry("translate", what) { g.translate(0.125, -1e-3) }
    }

    /// Replays the recording's calls (the first `limit` of them, or all) on
    /// one wrapper.
    static func replay<G: WrapperGeometry>(_: G.Type, _ r: Recording, fixed: Bool, limit: Int? = nil, _ x: ReplayObserver) {
        var inputs: [UInt32: G] = [:]
        func input(_ id: UInt32) -> G {
            if let g = inputs[id] { return g }
            var g = G.readWKB(r.geometries[id]!)
            if fixed {
                let g0 = g
                x.geometry("input setPrecision(0.01)", "#\(id)") { g0.setPrecision(0.01) }
                g = g0.setPrecision(0.01)
            } else {
                reading(x, "#\(id)", g)
            }
            inputs[id] = g
            return g
        }
        var prepared: [Double: G.PreparedType] = [:]
        var trees: [Double: G.TreeType] = [:]
        for c in r.calls.prefix(limit ?? r.calls.count) {
            let what = "\(r.name) \(c.name) \(c.geometries.prefix(4)) \(c.numbers)"
            let g = c.geometries.map(input), n = c.numbers
            func unary(_ f: (G) -> G) { x.geometry(c.name, what) { f(g[0]) } }
            func binary(_ f: (G, G) -> G) { x.geometry(c.name, what) { f(g[0], g[1]) } }
            switch c.name {
            case "isValid": x.same(c.name, what, g[0].isValid)
            case "area": x.same(c.name, what, bits(g[0].area))
            case "length": x.same(c.name, what, bits(g[0].length))
            case "bounds":
                let b = g[0].bounds
                x.same(c.name, what, [b.0, b.1, b.2, b.3].map(bits))
            case "centroid": unary { $0.centroid }
            case "representativePoint": unary { $0.representativePoint }
            case "description": x.same(c.name, what, g[0].description)
            case "buffer": unary { $0.styledBuffer(n[0], quadSegs: Int(n[1]), cap: Int32(n[2]), join: Int32(n[3]), mitreLimit: n[4]) }
            case "union": binary { $0.union($1) }
            case "intersection": binary { $0.intersection($1) }
            case "difference": binary { $0.difference($1) }
            case "unaryUnion": x.geometry(c.name, what) { G.makeUnaryUnion(g) }
            case "simplify": unary { $0.simplify(n[0]) }
            case "makeValid": unary { $0.makeValid() }
            case "setPrecision": unary { $0.setPrecision(n[0]) }
            case "convexHull": unary { $0.convexHull }
            case "envelope": unary { $0.envelope }
            case "boundary": unary { $0.boundary }
            case "minimumRotatedRectangle": unary { $0.minimumRotatedRectangle }
            case "offsetCurve": unary { $0.styledOffsetCurve(n[0], quadSegs: Int(n[1]), join: Int32(n[2]), mitreLimit: n[3]) }
            case "interpolate": unary { $0.interpolate(n[0], normalized: n[1] != 0) }
            case "project": x.same(c.name, what, bits(g[0].project(g[1])))
            case "distance": x.same(c.name, what, bits(g[0].distance(g[1])))
            case "intersects": x.same(c.name, what, g[0].intersects(g[1]))
            case "contains": x.same(c.name, what, g[0].contains(g[1]))
            case "within": x.same(c.name, what, g[0].within(g[1]))
            case "nearestPoints":
                let p = g[0].nearestPoints(g[1])
                x.same(c.name, what, bits(p.0) + bits(p.1))
            case "constrainedDelaunay":
                let t = g[0].constrainedDelaunay()
                x.same(c.name, what, [UInt64(t.count)] + t.flatMap { bits($0) })
            case "polygonize": x.geometry(c.name, what) { G.makePolygonize(g) }
            case "lineMerge": unary { $0.lineMerge() }
            case "Prepared.init": prepared[n[0]] = G.PreparedType(g[0])
            case "Prepared.contains", "Prepared.intersects":
                guard let p = prepared[n[0]] else { continue }
                x.same(c.name, what, c.name == "Prepared.contains" ? p.contains(g[0]) : p.intersects(g[0]))
            case "STRtree.init": trees[n[0]] = G.TreeType(g)
            case "STRtree.query":
                guard let t = trees[n[0]] else { continue }
                x.same(c.name, what, t.query(g[0]))
            case "STRtree.nearest":
                guard let t = trees[n[0]] else { continue }
                x.same(c.name, what, t.nearest(g[0]))
            default:
                x.unknown(c.name, what)
            }
        }
    }

    /// The replay on the new `Geometry`.
    static func run(_ r: Recording, fixed: Bool, limit: Int? = nil, _ x: ReplayObserver) {
        replay(Geometry.self, r, fixed: fixed, limit: limit, x)
    }

    /// The first calls of every recording, as recorded: quick enough for a
    /// debug build (a prefix of `everyCall`'s stored answers).
    @Test(.enabled(if: Recording.stored)) func firstCalls() throws {
        let t = WrapperTallies("wrapper replay (first 3000 calls)")
        for f in Recording.files() {
            let x = Observers.make("WrapperReplayTests.floating", .recording(f.name, limit: 32), t, partial: true)
            WrapperReplayTests.run(try Recording(url: f.url, name: f.name), fixed: false, limit: 3000, x)
            x.finish(sourceLocation: #_sourceLocation)
        }
        t.report()
    }

    /// Every call of every recording, as recorded and on the grid of 0.01
    /// (`TOPOLOGY_LONG_REPLAY=1`; minutes in an optimized build).
    @Test(.enabled(if: Recording.longStored)) func everyCall() throws {
        let floating = WrapperTallies("wrapper replay"), fixed = WrapperTallies("wrapper replay on the grid of 0.01")
        for f in Recording.files() {
            let r = try Recording(url: f.url, name: f.name)
            let a = Observers.make("WrapperReplayTests.floating", .recording(f.name, limit: 32), floating)
            WrapperReplayTests.run(r, fixed: false, a)
            a.finish(sourceLocation: #_sourceLocation)
            let b = Observers.make("WrapperReplayTests.fixed", .recording(f.name, limit: 32), fixed)
            WrapperReplayTests.run(r, fixed: true, b)
            b.finish(sourceLocation: #_sourceLocation)
        }
        floating.report()
        fixed.report()
    }

    /// The recorded geometries written by the port's `WKBWriter` are the
    /// bytes GEOS's writer recorded.
    @Test(.enabled(if: Recording.available)) func wkbWriting() throws {
        var tally = ParityTally("replay WKB writing")
        for f in Recording.files() {
            let r = try Recording(url: f.url, name: f.name)
            for (id, wkb) in r.geometries { tally.check(try Geometry.read(wkb: wkb).wkb == wkb, "\(r.name) #\(id)") }
        }
        tally.report()
    }
}
