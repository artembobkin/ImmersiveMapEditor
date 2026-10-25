import Foundation
import Testing
@testable import Geometry

extension GEOSSuite {
/// Phase 8's proof that the swap changes nothing: every recorded call of
/// `Geometry` replayed through the new `Geometry` (on `Topology`) and through
/// the old one on GEOS (`GEOSWrapper`, the wrapper as it stood), and the
/// results compared as they come, bit for bit: geometries by their kind,
/// their WKB (every coordinate's bits, the sign of zeros included) and the
/// grid of the precision model each part carries; numbers by their bits;
/// answers, indices and text exactly.
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
/// when GEOS itself gives another result within ten more runs, and is
/// counted apart; otherwise it is a difference. The suite is serialized:
/// the old wrapper has one GEOS context (its non-finite tests too, in
/// `Parity/WrapperNonFiniteTests`).
@Suite(.serialized)
struct WrapperReplayTests {
    typealias Old = GEOSWrapper.Geometry

    /// The tallies of one replay, by function.
    final class Tallies {
        var byName: [String: ParityTally] = [:]
        var zeroSigns: [String: Int] = [:]
        let label: String

        init(_ label: String) { self.label = label }

        func check(_ name: String, _ equal: Bool, _ detail: @autoclosure () -> String) {
            var t = byName[name] ?? ParityTally("\(label) \(name)")
            t.check(equal, detail())
            byName[name] = t
        }

        func report() {
            for name in byName.keys.sorted() {
                byName[name]!.report()
                if let z = zeroSigns[name] { print("parity \(label) \(name): \(z) equal but for the sign of zeros, GEOS's own randomness") }
            }
        }
    }

    /// The values and structure of a WKB: the doubles apart, so results can
    /// also be compared by value.
    static func split(_ wkb: [UInt8]) -> (structure: [UInt8], values: [Double]) {
        var structure: [UInt8] = [], values: [Double] = []
        var at = 0
        func u32() -> UInt32 {
            var v: UInt32 = 0
            for i in 0..<4 { v |= UInt32(wkb[at + i]) << (8 * i) }
            structure += wkb[at..<(at + 4)]
            at += 4
            return v
        }
        func f64() {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(wkb[at + i]) << (8 * i) }
            values.append(Double(bitPattern: v))
            at += 8
        }
        func geometry() {
            structure.append(wkb[at])
            at += 1
            switch u32() & 0xFF {
            case 1: f64(); f64()
            case 2: for _ in 0..<u32() { f64(); f64() }
            case 3: for _ in 0..<u32() { for _ in 0..<u32() { f64(); f64() } }
            default: for _ in 0..<u32() { geometry() }
            }
        }
        if !wkb.isEmpty { geometry() }
        return (structure, values)
    }

    static func equalByValue(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        let x = split(a), y = split(b)
        return x.structure == y.structure && x.values.count == y.values.count
            && zip(x.values, y.values).allSatisfy { $0 == $1 || ($0.isNaN && $1.isNaN) }
    }

    static func describe(_ g: Old) -> String { "\(g.kind) \(g.grids) \(g)" }
    static func describe(_ g: Geometry) -> String { "\(g.kind) \(g.grids) \(g)" }

    /// Compares a geometry result, running GEOS again where only the signs
    /// of zeros differ.
    static func compare(_ t: Tallies, _ name: String, _ what: @autoclosure () -> String,
                        _ old: () -> Old, _ new: () -> Geometry) {
        let a = old(), b = new()
        let wa = a.wkb, wb = b.wkb
        if a.kind.rawValue == b.kind.rawValue && wa == wb && a.grids.map(\.bitPattern) == b.grids.map(\.bitPattern) {
            return t.check(name, true, "")
        }
        if a.kind.rawValue == b.kind.rawValue && a.grids == b.grids && equalByValue(wa, wb) {
            if (0..<10).contains(where: { _ in old().wkb != wa }) {
                t.zeroSigns[name, default: 0] += 1
                return t.check(name, true, "")
            }
        }
        t.check(name, false, "\(what()): GEOS \(describe(a)) port \(describe(b))")
    }

    static func same<T: Equatable>(_ t: Tallies, _ name: String, _ what: @autoclosure () -> String, _ a: T, _ b: T) {
        t.check(name, a == b, "\(what()): GEOS \(a) port \(b)")
    }

    static func bits(_ v: Double) -> UInt64 { v.bitPattern }
    static func bits(_ p: SIMD2<Double>) -> [UInt64] { [p.x.bitPattern, p.y.bitPattern] }
    static func bits(_ ps: [SIMD2<Double>]) -> [UInt64] { ps.flatMap { bits($0) } }

    /// The inputs of one replay, read once by each side.
    final class Inputs {
        let recording: Recording
        let fixed: Bool
        let tallies: Tallies
        var old: [UInt32: Old] = [:]
        var new: [UInt32: Geometry] = [:]

        init(_ r: Recording, fixed: Bool, _ t: Tallies) {
            recording = r
            self.fixed = fixed
            tallies = t
        }

        func pair(_ id: UInt32) -> (Old, Geometry) {
            if let o = old[id], let n = new[id] { return (o, n) }
            let wkb = recording.geometries[id]!
            var o = Old.read(wkb: wkb), n = try! Geometry.read(wkb: wkb)
            if fixed {
                let (o0, n0) = (o, n)
                WrapperReplayTests.compare(tallies, "input setPrecision(0.01)", "#\(id)", { o0.setPrecision(0.01) }, { n0.setPrecision(0.01) })
                o = o0.setPrecision(0.01)
                n = n0.setPrecision(0.01)
            } else {
                WrapperReplayTests.reading(tallies, "#\(id)", o, n)
            }
            old[id] = o
            new[id] = n
            return (o, n)
        }
    }

    /// The reading API and the constructors on one geometry, and the
    /// geometries made from what was read.
    static func reading(_ t: Tallies, _ what: String, _ o: Old, _ n: Geometry) {
        same(t, "kind, isEmpty, isMulti", what, [Int(o.kind.rawValue), o.isEmpty ? 1 : 0, o.isMulti ? 1 : 0],
             [Int(n.kind.rawValue), n.isEmpty ? 1 : 0, n.isMulti ? 1 : 0])
        same(t, "x, y, coords", what, bits(o.xy) + bits(o.coords), bits(n.xy) + bits(n.coords))
        same(t, "exterior, interiors", what, bits(o.exterior) + o.interiors.flatMap { [0] + bits($0) },
             bits(n.exterior) + n.interiors.flatMap { [0] + bits($0) })
        same(t, "polygons, lines", what, [o.polygons.count, o.lines.count], [n.polygons.count, n.lines.count])
        let op = o.parts, np = n.parts
        same(t, "parts", what, op.map(\.wkb), np.map(\.wkb))
        same(t, "parts' grids", what, op.flatMap(\.grids).map(\.bitPattern), np.flatMap(\.grids).map(\.bitPattern))
        switch o.kind {
        case .point: compare(t, "point", what, { .point(o.xy) }, { .point(n.xy) })
        case .lineString, .linearRing:
            compare(t, "lineString", what, { .lineString(o.coords) }, { .lineString(n.coords) })
            let l = o.length
            compare(t, "substring", what, { o.substring(l * 0.2, l * 0.7) }, { n.substring(l * 0.2, l * 0.7) })
        case .polygon:
            compare(t, "polygon", what, { .polygon(o.exterior, holes: o.interiors) }, { .polygon(n.exterior, holes: n.interiors) })
            compare(t, "oriented", what, { o.oriented(1) }, { n.oriented(1) })
            compare(t, "oriented(-1)", what, { o.oriented(-1) }, { n.oriented(-1) })
        default:
            compare(t, "collection", what, { .collection(o.parts) }, { .collection(n.parts) })
        }
        compare(t, "map", what, { o.map { $0 * 1.5 + SIMD2(3, -7) } }, { n.map { $0 * 1.5 + SIMD2(3, -7) } })
        compare(t, "rotate", what, { o.rotate(17, origin: SIMD2(3, -4)) }, { n.rotate(17, origin: SIMD2(3, -4)) })
        compare(t, "scale", what, { o.scale(1.25, 0.75, origin: SIMD2(-2, 5)) }, { n.scale(1.25, 0.75, origin: SIMD2(-2, 5)) })
        compare(t, "translate", what, { o.translate(0.125, -1e-3) }, { n.translate(0.125, -1e-3) })
    }

    /// Replays the recording's calls (the first `limit` of them, or all).
    static func replay(_ r: Recording, fixed: Bool, limit: Int? = nil, _ t: Tallies) {
        let inputs = Inputs(r, fixed: fixed, t)
        var oldPrepared: [Double: GEOSWrapper.Prepared] = [:], newPrepared: [Double: Prepared] = [:]
        var oldTrees: [Double: GEOSWrapper.STRtree] = [:], newTrees: [Double: STRtree] = [:]
        for c in r.calls.prefix(limit ?? r.calls.count) {
            let what = "\(r.name) \(c.name) \(c.geometries.prefix(4)) \(c.numbers)"
            let g = c.geometries.map { inputs.pair($0) }
            let o = g.map(\.0), n = g.map(\.1), x = c.numbers
            func unary(_ old: (Old) -> Old, _ new: (Geometry) -> Geometry) { compare(t, c.name, what, { old(o[0]) }, { new(n[0]) }) }
            func binary(_ old: (Old, Old) -> Old, _ new: (Geometry, Geometry) -> Geometry) {
                compare(t, c.name, what, { old(o[0], o[1]) }, { new(n[0], n[1]) })
            }
            switch c.name {
            case "isValid": same(t, c.name, what, o[0].isValid, n[0].isValid)
            case "area": same(t, c.name, what, bits(o[0].area), bits(n[0].area))
            case "length": same(t, c.name, what, bits(o[0].length), bits(n[0].length))
            case "bounds":
                let a = o[0].bounds, b = n[0].bounds
                same(t, c.name, what, [a.0, a.1, a.2, a.3].map(bits), [b.0, b.1, b.2, b.3].map(bits))
            case "centroid": unary({ $0.centroid }, { $0.centroid })
            case "representativePoint": unary({ $0.representativePoint }, { $0.representativePoint })
            case "description": same(t, c.name, what, o[0].description, n[0].description)
            case "buffer":
                let cap = Geometry.Cap(rawValue: Int32(x[2]))!, join = Geometry.Join(rawValue: Int32(x[3]))!
                let oldCap = GEOSWrapper.Geometry.Cap(rawValue: Int32(x[2]))!, oldJoin = GEOSWrapper.Geometry.Join(rawValue: Int32(x[3]))!
                unary({ $0.buffer(x[0], quadSegs: Int(x[1]), cap: oldCap, join: oldJoin, mitreLimit: x[4]) },
                      { $0.buffer(x[0], quadSegs: Int(x[1]), cap: cap, join: join, mitreLimit: x[4]) })
            case "union": binary({ $0.union($1) }, { $0.union($1) })
            case "intersection": binary({ $0.intersection($1) }, { $0.intersection($1) })
            case "difference": binary({ $0.difference($1) }, { $0.difference($1) })
            case "unaryUnion": compare(t, c.name, what, { .unaryUnion(o) }, { .unaryUnion(n) })
            case "simplify": unary({ $0.simplify(x[0]) }, { $0.simplify(x[0]) })
            case "makeValid": unary({ $0.makeValid() }, { $0.makeValid() })
            case "setPrecision": unary({ $0.setPrecision(x[0]) }, { $0.setPrecision(x[0]) })
            case "convexHull": unary({ $0.convexHull }, { $0.convexHull })
            case "envelope": unary({ $0.envelope }, { $0.envelope })
            case "boundary": unary({ $0.boundary }, { $0.boundary })
            case "minimumRotatedRectangle": unary({ $0.minimumRotatedRectangle }, { $0.minimumRotatedRectangle })
            case "offsetCurve":
                let join = Geometry.Join(rawValue: Int32(x[2]))!, oldJoin = GEOSWrapper.Geometry.Join(rawValue: Int32(x[2]))!
                unary({ $0.offsetCurve(x[0], quadSegs: Int(x[1]), join: oldJoin, mitreLimit: x[3]) },
                      { $0.offsetCurve(x[0], quadSegs: Int(x[1]), join: join, mitreLimit: x[3]) })
            case "interpolate": unary({ $0.interpolate(x[0], normalized: x[1] != 0) }, { $0.interpolate(x[0], normalized: x[1] != 0) })
            case "project": same(t, c.name, what, bits(o[0].project(o[1])), bits(n[0].project(n[1])))
            case "distance": same(t, c.name, what, bits(o[0].distance(o[1])), bits(n[0].distance(n[1])))
            case "intersects": same(t, c.name, what, o[0].intersects(o[1]), n[0].intersects(n[1]))
            case "contains": same(t, c.name, what, o[0].contains(o[1]), n[0].contains(n[1]))
            case "within": same(t, c.name, what, o[0].within(o[1]), n[0].within(n[1]))
            case "nearestPoints":
                let a = o[0].nearestPoints(o[1]), b = n[0].nearestPoints(n[1])
                same(t, c.name, what, bits(a.0) + bits(a.1), bits(b.0) + bits(b.1))
            case "constrainedDelaunay":
                let a = o[0].constrainedDelaunay(), b = n[0].constrainedDelaunay()
                same(t, c.name, what, [UInt64(a.count)] + a.flatMap { bits($0) }, [UInt64(b.count)] + b.flatMap { bits($0) })
            case "polygonize": compare(t, c.name, what, { .polygonize(o) }, { .polygonize(n) })
            case "lineMerge": unary({ $0.lineMerge() }, { $0.lineMerge() })
            case "Prepared.init":
                oldPrepared[x[0]] = GEOSWrapper.Prepared(o[0])
                newPrepared[x[0]] = Prepared(n[0])
            case "Prepared.contains", "Prepared.intersects":
                guard let po = oldPrepared[x[0]], let pn = newPrepared[x[0]] else { continue }
                let isContains = c.name == "Prepared.contains"
                same(t, c.name, what, isContains ? po.contains(o[0]) : po.intersects(o[0]), isContains ? pn.contains(n[0]) : pn.intersects(n[0]))
            case "STRtree.init":
                oldTrees[x[0]] = GEOSWrapper.STRtree(o)
                newTrees[x[0]] = STRtree(n)
            case "STRtree.query":
                guard let to = oldTrees[x[0]], let tn = newTrees[x[0]] else { continue }
                same(t, c.name, what, to.query(o[0]), tn.query(n[0]))
            case "STRtree.nearest":
                guard let to = oldTrees[x[0]], let tn = newTrees[x[0]] else { continue }
                same(t, c.name, what, to.nearest(o[0]), tn.nearest(n[0]))
            default:
                t.check(c.name, false, "not replayed: \(c.name)")
            }
        }
    }

    /// The first calls of every recording, as recorded: quick enough for a
    /// debug build.
    @Test(.enabled(if: Recording.available)) func firstCalls() throws {
        let t = Tallies("wrapper replay (first 3000 calls)")
        for f in Recording.files() { WrapperReplayTests.replay(try Recording(url: f.url, name: f.name), fixed: false, limit: 3000, t) }
        t.report()
    }

    /// Every call of every recording, as recorded and on the grid of 0.01
    /// (`TOPOLOGY_LONG_REPLAY=1`; minutes in an optimized build).
    @Test(.enabled(if: Recording.longReplay)) func everyCall() throws {
        let floating = Tallies("wrapper replay"), fixed = Tallies("wrapper replay on the grid of 0.01")
        for f in Recording.files() {
            let r = try Recording(url: f.url, name: f.name)
            WrapperReplayTests.replay(r, fixed: false, floating)
            WrapperReplayTests.replay(r, fixed: true, fixed)
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
}
