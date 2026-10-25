import Foundation
import Testing
import Topology
import geos

/// The stored oracle's live mode (`TOPOLOGY_FREEZE=1`), while GEOS is still
/// in the package: every question asked of GEOS itself, through its C API
/// as the GEOS-backed tests asked it, and its answer written to the test's
/// tape for the frozen tests to read once GEOS is gone.
func liveOracle(_ name: String, _ store: TapeStore, _ writes: Bool) -> StoredOracle {
    LiveOracle(name, store, writes: writes)
}

final class LiveOracle: StoredOracle {
    let name: String
    let store: TapeStore
    let writes: Bool
    let o = GEOSOracle()
    let tape: TapeWriter
    /// The geometries of recorded inputs, read once.
    private var recorded: [UInt32: GEOSGeom] = [:]
    private var trees: [LiveTree] = []
    private var preparedGeometries: [GEOSPrepared] = []
    /// The current JTS case's inputs, as GEOS read them.
    private var jtsA: GEOSGeom?, jtsB: GEOSGeom?
    private var normalsApart = 0
    /// The GEOS geometries made for the current question, alive until the
    /// next one: a C call takes their pointers, which Swift does not see as uses.
    private var alive: [GEOSGeom] = []
    private var mismatches: [String] = []

    init(_ name: String, _ store: TapeStore, writes: Bool) {
        self.name = name
        self.store = store
        self.writes = writes
        tape = TapeWriter(url: store.writeURL(name), limit: store.limit)
    }

    func geos(_ i: OracleInput) -> GEOSGeom {
        switch i {
        case .shape(let s):
            let g = o.geometry(s)!
            alive.append(g)
            return g
        case .recorded(let id, let wkb):
            if let g = recorded[id] { return g }
            let g = o.read(wkb: wkb)!
            recorded[id] = g
            return g
        }
    }

    private func ask(_ q: Question) {
        alive.removeAll()
        q.align(&tape.alignment)
    }

    private var message: String? {
        let m = o.takeError()
        return store.keepsMessages ? m : nil
    }

    /// Writes a geometry GEOS gave (or its failure).
    private func write(_ g: GEOSGeom?, rerun: (() -> GEOSGeom?)?) -> GeometryAnswer {
        guard let g else {
            let m = message
            tape.failure(m)
            return .failure(m)
        }
        let raw = g.shape, normal = g.normalized.shape
        var varies = false
        if let rerun, LiveOracle.hasZero(normal) {
            varies = (0..<10).contains { _ in rerun().map { o.normalized($0).shape } != normal }
        }
        if tape.geometry((raw, normal, g.numGeometries, varies)) { normalsApart += 1 }
        // The answer whole, as the frozen side reads it when kept whole.
        return .result(StoredGeometry(kind: raw.kind, numGeometries: g.numGeometries, varies: varies, raw: .whole(raw.encoded()),
                                      normal: raw.isPortConstructible && raw.portNormalized == normal ? nil : .whole(normal.encoded())))
    }

    static func hasZero(_ s: Shape) -> Bool { s.coordinates.contains { $0 == 0 } || s.parts.contains(where: hasZero) }

    func compute(_ op: GeometryOp, _ g: [GEOSGeom]) -> GEOSGeom? {
        withExtendedLifetime(g) { computeAlive(op, g) }
    }

    private func computeAlive(_ op: GeometryOp, _ g: [GEOSGeom]) -> GEOSGeom? {
        let x = g.first
        switch op {
        case .envelope: return x!.unary(GEOSEnvelope_r)
        case .centroid: return x!.unary(GEOSGetCentroid_r)
        case .pointOnSurface: return x!.unary(GEOSPointOnSurface_r)
        case .convexHull: return x!.unary(GEOSConvexHull_r)
        case .boundary: return x!.unary(GEOSBoundary_r)
        case .minimumRotatedRectangle: return x!.unary(GEOSMinimumRotatedRectangle_r)
        case .normalize: return x!.normalized
        case .unaryUnion: return x!.unaryUnion
        case .makeValid: return x!.unary(GEOSMakeValid_r)
        case .lineMerge: return x!.unary(GEOSLineMerge_r)
        case .node: return x!.unary(GEOSNode_r)
        case .constrainedDelaunay: return x!.unary(GEOSConstrainedDelaunayTriangulation_r)
        case .setPrecision(let grid): return o.wrap(GEOSGeom_setPrecision_r(o.handle, x!.ptr, grid, 0))
        case .simplify(let d): return x!.unary(GEOSTopologyPreserveSimplify_r, d)
        case .interpolate(let d, let normalized):
            return o.wrap(normalized ? GEOSInterpolateNormalized_r(o.handle, x!.ptr, d) : GEOSInterpolate_r(o.handle, x!.ptr, d))
        case .buffer(let d, let q, let cap, let join, let mitre):
            return o.wrap(GEOSBufferWithStyle_r(o.handle, x!.ptr, d, Int32(q), Int32(cap), Int32(join), mitre))
        case .offsetCurve(let d, let q, let join, let mitre):
            return o.wrap(GEOSOffsetCurve_r(o.handle, x!.ptr, d, Int32(q), Int32(join), mitre))
        case .intersection: return x!.binary(g[1], GEOSIntersection_r)
        case .union: return x!.binary(g[1], GEOSUnion_r)
        case .difference: return x!.binary(g[1], GEOSDifference_r)
        case .symDifference: return x!.binary(g[1], GEOSSymDifference_r)
        case .overlayPrec(let code, let grid):
            let f: [Int: (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?, Double) -> OpaquePointer?] =
                [OverlayNG.intersection: GEOSIntersectionPrec_r, OverlayNG.union: GEOSUnionPrec_r,
                 OverlayNG.difference: GEOSDifferencePrec_r, OverlayNG.symDifference: GEOSSymDifferencePrec_r]
            return x!.binary(g[1], f[code]!, grid)
        case .polygonize:
            var ptrs: [OpaquePointer?] = g.map { $0.ptr }
            return withExtendedLifetime(g) { o.wrap(GEOSPolygonize_r(o.handle, &ptrs, UInt32(ptrs.count))) }
        }
    }

    func geometry(_ op: GeometryOp, _ inputs: [OracleInput], again: Bool) -> GeometryAnswer {
        ask(.geometry(op, inputs))
        let g = inputs.map(geos)
        return write(compute(op, g), rerun: again ? { self.compute(op, g) } : nil)
    }

    static func predicateFunction(_ op: PredicateOp) -> (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> Int8 {
        switch op {
        case .intersects: return GEOSIntersects_r
        case .contains: return GEOSContains_r
        case .within: return GEOSWithin_r
        case .covers: return GEOSCovers_r
        case .coveredBy: return GEOSCoveredBy_r
        case .touches: return GEOSTouches_r
        case .crosses: return GEOSCrosses_r
        case .overlaps: return GEOSOverlaps_r
        case .disjoint: return GEOSDisjoint_r
        case .equalsTopo: return GEOSEquals_r
        case .isValid: fatalError("unary")
        }
    }

    func predicate(_ op: PredicateOp, _ inputs: [OracleInput]) -> Bool? {
        ask(.predicate(op, inputs))
        let g = inputs.map(geos)
        let r = op == .isValid ? g[0].predicate(GEOSisValid_r) : g[0].predicate(g[1], LiveOracle.predicateFunction(op))
        if r == nil { _ = o.takeError() }
        tape.bool(r)
        return r
    }

    func measure(_ op: MeasureOp, _ inputs: [OracleInput]) -> Double? {
        ask(.measure(op, inputs))
        let g = inputs.map(geos)
        let r: Double?
        switch op {
        case .area: r = g[0].area
        case .length: r = g[0].length
        case .distance: r = g[0].measure(g[1], GEOSDistance_r)
        }
        if r == nil { _ = o.takeError() }
        tape.double(r)
        return r
    }

    func bounds(_ input: OracleInput) -> StoredBytes {
        ask(.bounds(input))
        let g = geos(input)
        var v = [0.0, 0, 0, 0]
        if !g.isEmpty {
            GEOSGeom_getXMin_r(g.handle, g.ptr, &v[0])
            GEOSGeom_getYMin_r(g.handle, g.ptr, &v[1])
            GEOSGeom_getXMax_r(g.handle, g.ptr, &v[2])
            GEOSGeom_getYMax_r(g.handle, g.ptr, &v[3])
        }
        tape.doubles(v)
        return .whole(TapeReader.encode(v))
    }

    func nearestPoints(_ a: OracleInput, _ b: OracleInput) -> StoredBytes? {
        ask(.nearestPoints(a, b))
        let ga = geos(a), gb = geos(b)
        var theirs: [Double]?
        if let seq = GEOSNearestPoints_r(o.handle, ga.ptr, gb.ptr) {
            var flat = [Double](repeating: 0, count: 4)
            GEOSCoordSeq_copyToBuffer_r(o.handle, seq, &flat, 0, 0)
            GEOSCoordSeq_destroy_r(o.handle, seq)
            theirs = flat
        } else {
            _ = o.takeError()
        }
        tape.doubles(theirs)
        return theirs.map { .whole(TapeReader.encode($0)) }
    }

    func validity(_ input: OracleInput) -> Verdict? {
        ask(.validity(input))
        let g = geos(input)
        var reason: UnsafeMutablePointer<CChar>?
        var location: OpaquePointer?
        let r = GEOSisValidDetail_r(g.handle, g.ptr, 0, &reason, &location)
        defer {
            if let reason { GEOSFree_r(g.handle, reason) }
            if let location { GEOSGeom_destroy_r(g.handle, location) }
        }
        if r == 2 {
            _ = o.takeError()
            tape.bool(nil)
            return nil
        }
        if r == 1 {
            tape.bool(true)
            return Verdict(valid: true, reason: "", location: [])
        }
        var x = 0.0, y = 0.0
        if let location {
            GEOSGeomGetX_r(g.handle, location, &x)
            GEOSGeomGetY_r(g.handle, location, &y)
        }
        let text = reason.map { String(cString: $0) } ?? ""
        tape.bool(false)
        tape.rawString(text)
        tape.raw { $0.u64(x.bitPattern); $0.u64(y.bitPattern) }
        return Verdict(valid: false, reason: text, location: [x.bitPattern, y.bitPattern])
    }

    func relate(_ a: OracleInput, _ b: OracleInput) -> Result<String, OracleFailure> {
        ask(.relate(a, b))
        let ga = geos(a), gb = geos(b)
        guard let s = GEOSRelate_r(o.handle, ga.ptr, gb.ptr) else {
            let m = o.takeError() ?? ""
            tape.failure(m)
            return .failure(OracleFailure(message: m))
        }
        let text = String(cString: s)
        GEOSFree_r(o.handle, s)
        tape.string(text)
        return .success(text)
    }

    func orientationIndex(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Int {
        ask(.orientationIndex(a, b, c))
        let r = Int(GEOSOrientationIndex_r(o.handle, a.x, a.y, b.x, b.y, c.x, c.y))
        tape.int(r)
        return r
    }

    func isCCW(_ ring: [Double]) -> Bool {
        ask(.isCCW(ring))
        let seq = GEOSCoordSeq_copyFromBuffer_r(o.handle, ring, UInt32(ring.count / 2), 0, 0)!
        defer { GEOSCoordSeq_destroy_r(o.handle, seq) }
        var ccw: Int8 = 0
        GEOSCoordSeq_isCCW_r(o.handle, seq, &ccw)
        tape.bool(ccw == 1)
        return ccw == 1
    }

    func segmentIntersection(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> SegmentAnswer {
        ask(.segmentIntersection(p1, p2, q1, q2))
        var cx = 0.0, cy = 0.0
        let r = Int(GEOSSegmentIntersection_r(o.handle, p1.x, p1.y, p2.x, p2.y, q1.x, q1.y, q2.x, q2.y, &cx, &cy))
        tape.int(r)
        if r == 1 { tape.doubles([cx, cy]) }
        return SegmentAnswer(result: r, point: r == 1 ? .whole(TapeReader.encode([cx, cy])) : nil)
    }

    func wkt(_ input: OracleInput) -> StoredBytes {
        ask(.wkt(input))
        let g = geos(input)
        let writer = GEOSWKTWriter_create_r(o.handle)
        defer { GEOSWKTWriter_destroy_r(o.handle, writer) }
        GEOSWKTWriter_setRoundingPrecision_r(o.handle, writer, 3)
        let s = GEOSWKTWriter_write_r(o.handle, writer, g.ptr)!
        defer { GEOSFree_r(o.handle, s) }
        let text = String(cString: s)
        tape.text(text)
        return .whole(Array(text.utf8))
    }

    func tree(_ items: [OracleInput]) -> Int {
        ask(.tree(items))
        trees.append(LiveTree(o, items.map(geos)))
        return trees.count - 1
    }

    func query(_ tree: Int, _ q: OracleInput) -> StoredBytes {
        ask(.query(q))
        let found = trees[tree].query(geos(q))
        tape.ints(found)
        return .whole(TapeReader.encode(found))
    }

    func nearest(_ tree: Int, _ q: OracleInput) -> Int? {
        ask(.nearest(q))
        let n = trees[tree].nearest(geos(q))
        tape.int(n)
        return n
    }

    func prepare(_ input: OracleInput) -> Int {
        ask(.prepare(input))
        preparedGeometries.append(geos(input).prepared())
        return preparedGeometries.count - 1
    }

    func prepared(_ op: PredicateOp, _ handle: Int, _ q: OracleInput) -> Bool? {
        ask(.prepared(op, q))
        let f: (GEOSContextHandle_t?, OpaquePointer?, OpaquePointer?) -> Int8
        switch op {
        case .contains: f = GEOSPreparedContains_r
        case .intersects: f = GEOSPreparedIntersects_r
        case .covers: f = GEOSPreparedCovers_r
        case .within: f = GEOSPreparedWithin_r
        default: fatalError("no prepared \(op)")
        }
        let r = preparedGeometries[handle].predicate(geos(q), f)
        if r == nil { _ = o.takeError() }
        tape.bool(r)
        return r
    }

    func project(_ line: OracleInput, _ point: OracleInput) -> Double {
        ask(.project(line, point))
        let r = GEOSProject_r(o.handle, geos(line).ptr, geos(point).ptr)
        _ = o.takeError()
        tape.double(r)
        return r
    }

    func read(_ input: OracleInput) -> GeometryAnswer {
        ask(.read(input))
        guard case .recorded(_, let wkb) = input else { fatalError("read of a shape") }
        return write(o.read(wkb: wkb), rerun: nil)
    }

    func linework(_ parts: [Shape], made: Shape?) {
        ask(.linework(parts))
        var lines: [OpaquePointer?] = []
        for p in parts {
            guard let g = o.geometry(p), let b = g.unary(GEOSBoundary_r) else { _ = o.takeError(); continue }
            alive += [g, b]
            lines.append(GEOSGeom_clone_r(o.handle, b.ptr))
        }
        var theirs: Shape?
        if !lines.isEmpty, let c = o.wrap(GEOSGeom_createCollection_r(o.handle, 7, &lines, UInt32(lines.count))), let u = c.unaryUnion {
            theirs = u.shape
        } else {
            _ = o.takeError()
        }
        tape.made(theirs)
        if theirs != made { mismatches.append("linework made with the port differs from GEOS's: \(made.map { "\($0)" } ?? "fails") vs \(theirs.map { "\($0)" } ?? "fails")") }
    }

    func jtsCase(_ file: JTSTestFile, _ c: JTSTestFile.Case) -> (a: Bool, b: Bool) {
        ask(.jtsCase(file.name, c.index))
        let engine = GEOSEngine(oracle: o)
        let ga = try? c.a.map { try engine.read($0, scale: file.fixedScale) }
        let gb = try? c.b.map { try engine.read($0, scale: file.fixedScale) }
        jtsA = ga ?? nil
        jtsB = gb ?? nil
        tape.bool(ga != nil)
        tape.bool(gb != nil)
        return (ga != nil, gb != nil)
    }

    func jtsEvaluate(_ file: JTSTestFile, _ t: JTSTestFile.Test) -> JTSAnswer {
        ask(.jtsEvaluate(t.index, t.operation))
        let engine = GEOSEngine(oracle: o)
        let target = t.target.uppercased() == "B" ? jtsB : jtsA
        guard let target, let v = try? engine.evaluate(t, target: target, a: jtsA, b: jtsB, file: file) else {
            _ = o.takeError()
            tape.bool(nil)
            return .none
        }
        switch v {
        case .geometry(let g): return .geometry(write(g, rerun: nil))
        case .boolean(let b): tape.bool(b); return .boolean(b)
        case .number(let d): tape.double(d); return .number(d)
        }
    }

    func jtsRead(_ text: String, scale: Double?) -> GeometryAnswer {
        ask(.jtsRead(text, scale))
        let g = try? GEOSEngine(oracle: o).read(text, scale: scale)
        if g == nil { _ = o.takeError() }
        return write(g, rerun: nil)
    }

    func finish(sourceLocation: SourceLocation) {
        for m in mismatches.prefix(5) { Issue.record(Comment(rawValue: "\(name): \(m)"), sourceLocation: sourceLocation) }
        print("oracle \(name): \(tape.entries) answers of GEOS, \(normalsApart) normal forms stored apart\(writes ? "" : " (not written)")")
        guard writes else { return }
        do { try tape.close() } catch { Issue.record("\(name): the tape cannot be written: \(error)", sourceLocation: sourceLocation) }
    }
}

/// GEOS's STR tree over geometries (node capacity 10), as `Geometry`'s
/// `STRtree` drove it.
final class LiveTree {
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
