import Foundation
import Testing
@testable import Topology
import geos

/// One case run on both sides, to study a difference: `DEBUG_OP` names the
/// operation (`intersection`, `union`, `difference`, `symDifference`,
/// `unaryUnion`), `DEBUG_A` and `DEBUG_B` hold the inputs' WKT (or name
/// files holding them). Runs only when `DEBUG_OP` is set.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DEBUG_OP"] != nil))
struct DebugCaseTests {
    static func text(_ key: String) -> String? {
        guard let v = ProcessInfo.processInfo.environment[key] else { return nil }
        if FileManager.default.fileExists(atPath: v) { return try? String(contentsOfFile: v, encoding: .utf8) }
        return v
    }

    @Test func runCase() throws {
        let env = ProcessInfo.processInfo.environment
        let op = env["DEBUG_OP"]!
        let o = GEOSOracle()
        let a = try WKTReader().read(DebugCaseTests.text("DEBUG_A")!)
        let b = try DebugCaseTests.text("DEBUG_B").map { try WKTReader().read($0) }
        let ga = o.geos(a), gb = b.map { o.geos($0) }
        let theirs: GEOSGeom?
        let run: () throws -> Topology.Geometry
        switch op {
        case "intersection": theirs = ga.binary(gb!, GEOSIntersection_r); run = { try a.intersection(b!) }
        case "union": theirs = ga.binary(gb!, GEOSUnion_r); run = { try a.union(b!) }
        case "difference": theirs = ga.binary(gb!, GEOSDifference_r); run = { try a.difference(b!) }
        case "symDifference": theirs = ga.binary(gb!, GEOSSymDifference_r); run = { try a.symDifference(b!) }
        case "unionWithEmpty":
            let e = o.read(wkt: "GEOMETRYCOLLECTION EMPTY")!
            theirs = ga.binary(e, GEOSUnionPrec_r, 0)
            run = { try OverlayNGRobust.overlay(a, a.factory.createGeometryCollection(), OverlayNG.union) }
        case "prec":
            // An overlay at a fixed precision, GEOS run 20 times to see whether
            // its result varies (its hot pixel index shuffles at random).
            let code = Int(env["DEBUG_CODE"]!)!, grid = Double(env["DEBUG_GRID"]!)!
            let fs: [Int: (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?, Double) -> OpaquePointer?] =
                [1: GEOSIntersectionPrec_r, 2: GEOSUnionPrec_r, 3: GEOSDifferencePrec_r, 4: GEOSSymDifferencePrec_r]
            var seen: [String: Int] = [:]
            for _ in 0..<20 { seen["\(ga.binary(gb!, fs[code]!, grid).map { $0.normalized.shape.description } ?? "fails")", default: 0] += 1 }
            print("debug GEOS distinct normalized results over 20 runs: \(seen.count)")
            theirs = ga.binary(gb!, fs[code]!, grid)
            run = { try OverlayNG.overlay(a, b!, code, PrecisionModel(scale: 1.0 / grid)) }
        case "buffer":
            let d = Double(env["DEBUG_DIST"] ?? "0")!
            theirs = ga.unary(GEOSBuffer_r, d, 8)
            run = { try a.buffer(d) }
        case "setPrecision":
            let grid = Double(env["DEBUG_GRID"]!)!
            theirs = o.wrap(GEOSGeom_setPrecision_r(o.handle, ga.ptr, grid, 0))
            run = {
                print("debug reduced: \(try PrecisionReducer.reducePrecision(a, PrecisionModel(scale: 1 / grid)))")
                return try a.setPrecision(grid)
            }
        case "cdt":
            FileHandle.standardError.write(Data("debug calling GEOS\n".utf8))
            theirs = ga.unary(GEOSConstrainedDelaunayTriangulation_r)
            FileHandle.standardError.write(Data("debug GEOS returned\n".utf8))
            run = { try ConstrainedDelaunayTriangulator.triangulate(a) }
        case "makeValid":
            theirs = ga.unary(GEOSMakeValid_r)
            run = { try a.makeValid() }
            NonFinite.trace = { print("debug raise:\n" + Thread.callStackSymbols.prefix(14).joined(separator: "\n")) }
        default: theirs = ga.unaryUnion; run = { try a.union() }
        }
        print("debug GEOS: \(theirs.map { "\($0.shape)" } ?? "fails: \(o.takeError() ?? "")")")
        OverlayNGRobust.trace = { print("debug trace: \($0)") }
        let mine = Result { try run() }
        OverlayNGRobust.trace = nil
        if env["DEBUG_EDGES"] != nil, let b {
            let builder = EdgeNodingBuilder(.floating, nil)
            for e in try builder.build(a, b) {
                print("debug edge: \(e.pts.map { "\($0.x) \($0.y)" }.joined(separator: ", "))")
            }
        }
        if env["DEBUG_CASCADE"] != nil {
            var polys: [Polygon] = []
            a.applyGeometries { if let p = $0 as? Polygon { polys.append(p) } }
            let tree = STRtree<Polygon>(nodeCapacity: 10)
            for p in polys { tree.insert(p.getEnvelopeInternal(), p) }
            let geoms = tree.itemsInPackedOrder()
            print("debug cascade: \(geoms.count) polygons")
            var reported = false
            func cascade(_ s: Int, _ e: Int) -> (Topology.Geometry, GEOSGeom)? {
                if e - s == 1 { return (geoms[s], o.geos(geoms[s])) }
                let (l, r): ((Topology.Geometry, GEOSGeom)?, (Topology.Geometry, GEOSGeom)?)
                if e - s == 2 { (l, r) = (cascade(s, s + 1), cascade(s + 1, e)) } else {
                    let mid = (e + s) / 2
                    (l, r) = (cascade(s, mid), cascade(mid, e))
                }
                guard let l, let r else { return nil }
                let pu = try? l.0.union(r.0)
                var gu = l.1.binary(r.1, GEOSUnion_r)
                if gu == nil {
                    print("debug cascade GEOS union fails at \(s)..<\(e): \(o.takeError() ?? "")")
                    let gc = o.geos(a.factory.createGeometryCollection([l.0, r.0]))
                    gu = gc.unary(GEOSBuffer_r, 0, 8)
                    print("debug cascade GEOS buffer: \(gu == nil ? "fails \(o.takeError() ?? "")" : "ok"); port buffer: \((try? a.factory.createGeometryCollection([l.0, r.0]).buffer(0)) == nil ? "fails" : "ok")")
                }
                guard let pu, let gu else { print("debug cascade: a side fails"); return nil }
                if Shape(pu) != gu.shape && !reported {
                    reported = true
                    print("debug cascade differs at \(s)..<\(e)")
                    print("debug cascade A: \(Shape(l.0))")
                    print("debug cascade B: \(Shape(r.0))")
                    print("debug cascade A equal: \(Shape(l.0) == l.1.shape) B equal: \(Shape(r.0) == r.1.shape)")
                }
                return (pu, gu)
            }
            _ = cascade(0, geoms.count)
        }
        if env["DEBUG_PARTS"] != nil {
            var polys: [Polygon] = [], lines: [LineString] = []
            a.applyGeometries { g in
                if let p = g as? Polygon { polys.append(p) }
                if let l = g as? LineString { lines.append(l) }
            }
            let mp = a.factory.createMultiPolygon(polys), ml = a.factory.createMultiLineString(lines)
            let pp = try? mp.union(), pl = try? ml.union()
            let gp = o.geos(mp).unaryUnion, gl = o.geos(ml).unaryUnion
            print("debug parts polygons: port \(pp.map { "\(Shape($0))".prefix(200) } ?? "fails") GEOS \(gp.map { "\($0.shape)".prefix(200) } ?? "fails \(o.takeError() ?? "")")")
            print("debug parts polygons equal: \(pp.map { Shape($0) } == gp?.shape)  lines equal: \(pl.map { Shape($0) } == gl?.shape)")
            if let pp, let pl, let gp, let gl {
                let pu = Result { try pl.union(pp) }
                let gu = gl.binary(gp, GEOSUnion_r)
                print("debug parts lines with polygons: port \((try? pu.get()) == nil ? "fails" : "ok") GEOS \(gu == nil ? "fails \(o.takeError() ?? "")" : "ok")")
            }
        }
        if env["DEBUG_TRIPLES"] != nil {
            var polys: [Polygon] = []
            a.applyGeometries { if let p = $0 as? Polygon { polys.append(p) } }
            for i in polys.indices {
                let rest = polys.indices.filter { $0 != i }
                guard rest.count == 2 else { continue }
                func step(_ x: Topology.Geometry, _ y: Topology.Geometry) -> Topology.Geometry? {
                    do { return try GeometryOverlay.heuristicOverlay(x, y, OverlayNG.union) } catch {
                        let gc = a.factory.createGeometryCollection([x, y])
                        let gb = o.geos(gc).unary(GEOSBuffer_r, 0, 8)
                        let pb = Result { try gc.buffer(0) }
                        print("debug triple overlay fails (\(error)); buffer GEOS \(gb == nil ? "fails \(o.takeError() ?? "")" : "ok") port \((try? pb.get()) == nil ? "fails" : "ok") equal \((try? pb.get()).map { o.normalizedShapes($0, gb!).0 == o.normalizedShapes($0, gb!).1 } ?? false)")
                        if let env = ProcessInfo.processInfo.environment["DEBUG_SAVE"] { try? "\(gc)".write(toFile: env, atomically: true, encoding: .utf8) }
                        return try? pb.get()
                    }
                }
                guard let u = step(polys[rest[0]], polys[rest[1]]) else { continue }
                print("debug triple \(i) with \(rest): \(step(polys[i], u) == nil ? "fails" : "ok")")
            }
        }
        if env["DEBUG_PAIRS"] != nil {
            var polys: [Polygon] = []
            a.applyGeometries { if let p = $0 as? Polygon { polys.append(p) } }
            for i in polys.indices {
                for j in polys.indices where j > i {
                    let gc = a.factory.createGeometryCollection([polys[i], polys[j]])
                    let gb = o.geos(gc).unary(GEOSBuffer_r, 0, 8)
                    let gu = o.geos(polys[i]).binary(o.geos(polys[j]), GEOSUnion_r)
                    let pb = Result { try gc.buffer(0) }
                    let pu = Result { try polys[i].union(polys[j]) }
                    print("debug pair \(i) \(j): GEOS union \(gu == nil ? "fails \(o.takeError() ?? "")" : "ok") buffer \(gb == nil ? "fails \(o.takeError() ?? "")" : "ok"); port union \((try? pu.get()) == nil ? "fails" : "ok") buffer \((try? pb.get()) == nil ? "fails" : "ok")")
                }
            }
        }
        if env["DEBUG_NODE"] != nil {
            let lines = Shape(a.factory.createMultiLineString(NodingParityTests.lines(a).map { a.factory.createLineString(CoordinateArrays.removeRepeatedPoints($0)) }))
            let g = o.geometry(lines)!.unary(GEOSNode_r)
            let m = try? NodingParityTests.node(lines.topology())
            print("debug GEOSNode equal: \(m.map { Shape($0) } == g?.shape)")
            print("debug GEOSNode GEOS: \(g.map { "\($0.shape)" } ?? "fails")")
            print("debug GEOSNode port: \(m.map { "\(Shape($0))" } ?? "fails")")
        }
        if let tol = env["DEBUG_SNAP"].flatMap(Double.init) {
            var rings: [SegmentString] = []
            a.applyComponents { if let r = $0 as? LinearRing { rings.append(NodedSegmentString(CoordinateArrays.removeRepeatedPoints(r.points), nil)) } }
            let noder = SnappingNoder(tol)
            noder.computeNodes(rings)
            for s in noder.getNodedSubstrings() { print("debug noded: \(s.getCoordinates().map { "\($0.x) \($0.y)" }.joined(separator: ", "))") }
        }
        if let b, let code = ["intersection": 1, "union": 2, "difference": 3, "symDifference": 4][op] {
            do {
                print("debug port floating: \(Shape(try OverlayNG.overlay(a, b, code, .floating)))")
            } catch { print("debug port floating fails: \(error)") }
            var tol = OverlayNGRobust.snapTolerance(a, b)
            for _ in 0..<5 {
                do {
                    print("debug port snap \(tol): \(Shape(try OverlayNG.overlay(a, b, code, noder: SnappingNoder(tol))))")
                } catch { print("debug port snap \(tol) fails: \(error)") }
                for (name, g) in [("A", a), ("B", b)] {
                    do {
                        print("debug port snapSelf \(name) \(tol): \(Shape(try OverlayNG.union(g, nil, SnappingNoder(tol))))")
                    } catch { print("debug port snapSelf \(name) \(tol) fails: \(error)") }
                }
                tol *= 10
            }
        }
        switch mine {
        case .success(let g): print("debug port: \(Shape(g))")
        case .failure(let e): print("debug port fails: \(e)")
        }
    }
}
