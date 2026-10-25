import Foundation
import Testing
import Topology

/// The overlays against GEOS 3.13's stored answers (`GEOSIntersection`,
/// `GEOSUnion`, `GEOSDifference`, `GEOSSymDifference`, `GEOSUnaryUnion` and
/// the `Prec` overlays at a fixed precision), on seeded random pairs that
/// overlap and on near-degenerate ones (shared edges, tiny shifts, the same
/// geometry twice, collinear vertices). Results in GEOS's normal form, bit
/// for bit; where GEOS failed, the port must throw. The results as they come
/// (not normalized) are counted too: GEOS's order of rings and points.
@Suite struct OverlayParityTests {
    /// Every coordinate of a shape moved by `f`.
    static func mapped(_ s: Shape, _ f: (Double, Double) -> (Double, Double)) -> Shape {
        var r = s
        r.coordinates = stride(from: 0, to: s.coordinates.count, by: 2).flatMap { i -> [Double] in
            let p = f(s.coordinates[i], s.coordinates[i + 1])
            return [p.0, p.1]
        }
        r.parts = s.parts.map { mapped($0, f) }
        return r
    }

    /// The centre and size of a shape's coordinates.
    static func frame(_ s: Shape) -> (Double, Double, Double)? {
        var xs: [Double] = [], ys: [Double] = []
        func walk(_ t: Shape) {
            for i in stride(from: 0, to: t.coordinates.count, by: 2) { xs.append(t.coordinates[i]); ys.append(t.coordinates[i + 1]) }
            t.parts.forEach(walk)
        }
        walk(s)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return ((minX + maxX) / 2, (minY + maxY) / 2, max(maxX - minX, maxY - minY))
    }

    /// A second geometry that meets the first: another random one moved onto
    /// it, or the first itself shifted a little, shifted a tiny bit, turned
    /// half round about its centre, or the same.
    static func partner(_ a: Shape, _ r: inout RandomGeometries) -> Shape {
        guard let (cx, cy, size) = frame(a) else { return r.geometry() }
        switch r.int(0...9) {
        case 0...4:
            let b = r.geometry()
            guard let (bx, by, bs) = frame(b), bs > 0 else { return b }
            let k = size > 0 ? size / bs * r.double(0.3...1.5) : 1
            let ox = cx + size * r.double(-0.5...0.5), oy = cy + size * r.double(-0.5...0.5)
            return mapped(b) { ((($0 - bx) * k) + ox, (($1 - by) * k) + oy) }
        case 5:
            let dx = size * r.double(-0.4...0.4), dy = size * r.double(-0.4...0.4)
            return mapped(a) { ($0 + dx, $1 + dy) }
        case 6:
            let d = size * 1e-10 * r.double(-1...1)
            return mapped(a) { ($0 + d, $1 - d) }
        case 7:
            return mapped(a) { (2 * cx - $0, 2 * cy - $1) }
        case 8:
            // Along an axis by a whole part of the size: edges shared exactly
            // when the coordinates are on a grid.
            let d = size / 4
            return mapped(a) { ($0 + d, $1) }
        default:
            return a
        }
    }

    struct Tallies {
        var normal: ParityTally
        var raw = 0
        var failingBoth = 0
        /// Equal but for the sign of zeros (accepted, counted apart).
        var zeroSign = 0
        /// Of those, the inputs on which GEOS itself gave different results
        /// from run to run (its snap rounding shuffles at random), as found
        /// when its answers were stored.
        var zeroSignGEOSVaries = 0

        init(_ name: String) { normal = ParityTally(name) }

        mutating func report() {
            normal.report()
            let results = normal.compared - failingBoth
            print("parity \(normal.name): GEOS and the port failing alike \(failingBoth), results raw (not normalized) equal \(raw) of \(results)")
            if zeroSign > 0 {
                print("parity \(normal.name): \(zeroSign) equal but for the sign of zeros, GEOS varying run to run on \(zeroSignGEOSVaries) of them")
            }
        }
    }

    /// Compares one operation's result with GEOS's. A result equal to GEOS's
    /// but for the sign of zeros is accepted and counted apart.
    static func compare(_ input: @autoclosure () -> String, _ mine: () throws -> Topology.Geometry,
                        _ theirs: GeometryAnswer, _ t: inout Tallies) {
        let m = Result { try mine() }
        switch (m, theirs) {
        case (.failure, .failure):
            t.failingBoth += 1
            t.normal.check(true, "")
        case (.failure(let e), .result(let g)):
            t.normal.check(false, "\(input()): the port fails (\(e)), GEOS gives \(g.description)")
        case (.success(let p), .failure(let message)):
            t.normal.check(false, "\(input()): GEOS fails (\(message ?? "")), the port gives \(Shape(p))")
        case (.success(let p), .result(let g)):
            let a = Shape(p.norm()), raw = Shape(p)
            let match = g.compare(raw: raw, normal: a)
            if match == .zeroSign {
                t.zeroSign += 1
                if g.varies { t.zeroSignGEOSVaries += 1 }
                ParityTally.dump("\(t.normal.name) zero sign: \(input())\n  port \(a)\n  GEOS \(g.normalDescription)")
                t.normal.check(true, "")
                return
            }
            t.normal.check(match == .equal, "\(input()):\n  port \(a)\n  GEOS \(g.normalDescription)")
            if g.rawEquals(raw) {
                t.raw += 1
            } else if ProcessInfo.processInfo.environment["PARITY_DUMP_RAW"] != nil {
                ParityTally.dump("\(t.normal.name) raw: \(input())\n  port \(raw)\n  GEOS \(g.description)")
            }
        }
    }

    static let binaryOps: [(String, (Topology.Geometry, Topology.Geometry) throws -> Topology.Geometry, GeometryOp)] = [
        ("intersection", { try $0.intersection($1) }, .intersection),
        ("union", { try $0.union($1) }, .union),
        ("difference", { try $0.difference($1) }, .difference),
        ("symDifference", { try $0.symDifference($1) }, .symDifference),
    ]

    @Test(arguments: 0..<4) func binaryOverlay(_ op: Int) {
        let (name, mine, theirs) = OverlayParityTests.binaryOps[op]
        let o = Oracles.make("OverlayParityTests.binaryOverlay.\(op)")
        defer { o.finish() }
        var t = Tallies(name)
        var r = RandomGeometries(seed: 400 + UInt64(op))
        for _ in 0..<4000 {
            let a = r.geometry()
            let b = OverlayParityTests.partner(a, &r)
            OverlayParityTests.compare("\(a) \(name) \(b)", { try mine(a.topology(), b.topology()) },
                                       o.geometry(theirs, [.shape(a), .shape(b)], again: true), &t)
        }
        t.report()
    }

    @Test func unaryUnion() {
        let o = Oracles.make("OverlayParityTests.unaryUnion")
        defer { o.finish() }
        var t = Tallies("unaryUnion")
        var r = RandomGeometries(seed: 410)
        for _ in 0..<2000 {
            let a = r.geometry()
            var parts = [a]
            for _ in 0..<r.int(1...6) { parts.append(OverlayParityTests.partner(a, &r)) }
            let kinds = Set(parts.map(\.kind))
            let kind: Shape.Kind = kinds == [.polygon] ? .multiPolygon : (kinds == [.lineString] ? .multiLineString : .geometryCollection)
            let s = Shape(kind: kind, parts: parts.flatMap { $0.kind.rawValue >= 4 ? $0.parts : [$0] }.filter { !$0.isEmpty })
            OverlayParityTests.compare("\(s)", { try s.topology().union() }, o.geometry(.unaryUnion, [.shape(s)]), &t)
        }
        t.report()
    }

    static let precOps = [OverlayNG.intersection, OverlayNG.union, OverlayNG.difference, OverlayNG.symDifference]

    /// OverlayNG with snap rounding at a fixed precision, as the `Prec`
    /// functions run it (GEOS's grid size is the precision's 1 / scale).
    @Test(arguments: 0..<4) func fixedPrecisionOverlay(_ op: Int) {
        let code = OverlayParityTests.precOps[op]
        let o = Oracles.make("OverlayParityTests.fixedPrecisionOverlay.\(op)")
        defer { o.finish() }
        var t = Tallies("Prec overlay \(code)")
        var r = RandomGeometries(seed: 420 + UInt64(op))
        for _ in 0..<2000 {
            let a = r.geometry()
            let b = OverlayParityTests.partner(a, &r)
            guard let (_, _, size) = OverlayParityTests.frame(a), size > 0 else { continue }
            let grid = [size / 7, size / 100, size / 1e4, 1.0, 0.001].randomElement(using: &r.rng)!
            OverlayParityTests.compare("\(a) op \(code) \(b) grid \(grid)", {
                try OverlayNG.overlay(a.topology(), b.topology(), code, PrecisionModel(scale: 1.0 / grid))
            }, o.geometry(.overlayPrec(code, grid: grid), [.shape(a), .shape(b)], again: true), &t)
        }
        t.report()
    }
}
