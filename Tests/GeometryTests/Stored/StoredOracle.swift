import Foundation
import Testing
import Topology

/// What a parity test asks GEOS 3.13, and GEOS's answer. Since phase 12
/// the answers come from tapes (`FrozenOracle`): stored from GEOS when the
/// test last ran against it, read back in the same order. Each question
/// names the GEOS function it stood for.
protocol StoredOracle: AnyObject {
    /// A geometry operation: GEOS's result or its failure. `again`: whether
    /// GEOS's randomness (the sign of zeros) is checked for this operation.
    func geometry(_ op: GeometryOp, _ inputs: [OracleInput], again: Bool) -> GeometryAnswer
    func predicate(_ op: PredicateOp, _ inputs: [OracleInput]) -> Bool?
    func measure(_ op: MeasureOp, _ inputs: [OracleInput]) -> Double?
    /// `GEOSGeom_getXMin` and the other three (zeros for an empty geometry), as stored.
    func bounds(_ input: OracleInput) -> StoredBytes
    /// `GEOSNearestPoints`: the two points as stored, nil when GEOS fails.
    func nearestPoints(_ a: OracleInput, _ b: OracleInput) -> StoredBytes?
    /// `GEOSisValidDetail`.
    func validity(_ input: OracleInput) -> Verdict?
    /// `GEOSRelate`: the matrix, or GEOS's message when it fails.
    func relate(_ a: OracleInput, _ b: OracleInput) -> Result<String, OracleFailure>
    /// `GEOSOrientationIndex`.
    func orientationIndex(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Int
    /// `GEOSCoordSeq_isCCW` of a ring's coordinates.
    func isCCW(_ ring: [Double]) -> Bool
    /// `GEOSSegmentIntersection`: its return value and the point.
    func segmentIntersection(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> SegmentAnswer
    /// GEOS's WKT writer at rounding precision 3, as stored (whole or a digest).
    func wkt(_ input: OracleInput) -> StoredBytes
    /// `GEOSSTRtree_create` (capacity 10) with the items inserted: a handle.
    func tree(_ items: [OracleInput]) -> Int
    /// `GEOSSTRtree_query`: the indices found, sorted, as stored.
    func query(_ tree: Int, _ q: OracleInput) -> StoredBytes
    /// `GEOSSTRtree_nearest` (the distance `GEOSDistance`).
    func nearest(_ tree: Int, _ q: OracleInput) -> Int?
    /// `GEOSPrepare`: a handle.
    func prepare(_ input: OracleInput) -> Int
    func prepared(_ op: PredicateOp, _ handle: Int, _ q: OracleInput) -> Bool?
    /// `GEOSProject`, its value as it is (-1 when GEOS fails).
    func project(_ line: OracleInput, _ point: OracleInput) -> Double
    /// Whether GEOS can read a recorded geometry, and what it reads.
    func read(_ input: OracleInput) -> GeometryAnswer
    /// The noded linework of the lines tests, which they made with GEOS
    /// (`GEOSBoundary` of each part but collections, `GEOSUnaryUnion` of
    /// them as a collection): made now with the port (`made`, nil where the
    /// union fails) and checked against GEOS's, so the inputs are GEOS's.
    func linework(_ parts: [Shape], made: Shape?)
    /// The JTS XML tests: GEOS's reading of a case's inputs (whether it
    /// read them), and its result of one test of the case.
    func jtsCase(_ file: JTSTestFile, _ c: JTSTestFile.Case) -> (a: Bool, b: Bool)
    func jtsEvaluate(_ file: JTSTestFile, _ t: JTSTestFile.Test) -> JTSAnswer
    func jtsRead(_ text: String, scale: Double?) -> GeometryAnswer
    /// The end of the test: the tape is checked (frozen) or written (live).
    func finish(sourceLocation: SourceLocation)
}

extension StoredOracle {
    func geometry(_ op: GeometryOp, _ inputs: [OracleInput]) -> GeometryAnswer { geometry(op, inputs, again: false) }
    func finish(_ sourceLocation: SourceLocation = #_sourceLocation) { finish(sourceLocation: sourceLocation) }
}

/// An input of a question: a shape the test made, or a recorded geometry.
enum OracleInput {
    case shape(Shape)
    case recorded(UInt32, [UInt8])

    /// What the alignment digest takes of it.
    func align(_ d: inout Digest) {
        switch self {
        case .shape(let s): d.add(Digest.of(s.encoded()))
        case .recorded(let id, _): d.add(Int(id))
        }
    }
}

struct OracleFailure: Error {
    var message: String?
}

/// GEOS's `isValidDetail`: valid, or the reason and the location's bits.
struct Verdict: Equatable, CustomStringConvertible {
    var valid: Bool
    var reason: String
    var location: [UInt64]

    var description: String { valid ? "valid" : "\(reason) at \(location.map { Double(bitPattern: $0) })" }
}

/// `GEOSSegmentIntersection`'s return value, and the point where it is 1.
struct SegmentAnswer: Equatable {
    var result: Int
    var point: StoredBytes?
}

/// GEOS's result of a JTS XML test, by kind.
enum JTSAnswer {
    case geometry(GeometryAnswer)
    case boolean(Bool)
    case number(Double)
    /// GEOS's engine threw.
    case none
}

/// The geometry operations, as the GEOS function each stands for.
enum GeometryOp {
    case envelope, centroid, pointOnSurface, convexHull, boundary, minimumRotatedRectangle
    /// `GEOSNormalize` of the input.
    case normalize
    case unaryUnion, makeValid, lineMerge, node, constrainedDelaunay
    case setPrecision(Double)
    case simplify(Double)
    case interpolate(Double, normalized: Bool)
    /// `GEOSBufferWithStyle`.
    case buffer(Double, quadSegs: Int, cap: Int, join: Int, mitreLimit: Double)
    case offsetCurve(Double, quadSegs: Int, join: Int, mitreLimit: Double)
    case intersection, union, difference, symDifference
    /// `GEOSIntersectionPrec` and the others, by OverlayNG's code, at the grid.
    case overlayPrec(Int, grid: Double)
    /// `GEOSPolygonize` of the inputs as a list.
    case polygonize

    var code: Int {
        switch self {
        case .envelope: return 1
        case .centroid: return 2
        case .pointOnSurface: return 3
        case .convexHull: return 4
        case .boundary: return 5
        case .minimumRotatedRectangle: return 6
        case .normalize: return 7
        case .unaryUnion: return 8
        case .makeValid: return 9
        case .lineMerge: return 10
        case .node: return 11
        case .constrainedDelaunay: return 12
        case .setPrecision: return 13
        case .simplify: return 14
        case .interpolate: return 15
        case .buffer: return 16
        case .offsetCurve: return 17
        case .intersection: return 18
        case .union: return 19
        case .difference: return 20
        case .symDifference: return 21
        case .overlayPrec: return 22
        case .polygonize: return 23
        }
    }

    func align(_ d: inout Digest) {
        d.add(code)
        switch self {
        case .setPrecision(let g), .simplify(let g): d.add(g)
        case .interpolate(let x, let n): d.add(x); d.add(n ? 1 : 0)
        case .buffer(let x, let q, let c, let j, let m): d.add(x); d.add(q); d.add(c); d.add(j); d.add(m)
        case .offsetCurve(let x, let q, let j, let m): d.add(x); d.add(q); d.add(j); d.add(m)
        case .overlayPrec(let c, let g): d.add(c); d.add(g)
        default: break
        }
    }
}

enum PredicateOp: String {
    case intersects, contains, within, covers, coveredBy, touches, crosses, overlaps, disjoint, equalsTopo
    /// `GEOSisValid` of the one input.
    case isValid

    var code: Int {
        switch self {
        case .intersects: return 1
        case .contains: return 2
        case .within: return 3
        case .covers: return 4
        case .coveredBy: return 5
        case .touches: return 6
        case .crosses: return 7
        case .overlaps: return 8
        case .disjoint: return 9
        case .equalsTopo: return 10
        case .isValid: return 11
        }
    }
}

enum MeasureOp: Int {
    case area = 1, length, distance
}

/// Where the tapes are: the fixtures in git (`.oracle` beside these
/// sources, hidden from SwiftPM, so `Package.swift` needs no resources),
/// and the expectations of the recorded calls beside the recordings,
/// outside git (`.build/recording/expected/<recording>/`).
enum TapeStore {
    case fixtures
    case recording(String, limit: Int = 1024)

    /// The largest payload a tape keeps whole: small in git, generous beside
    /// the recordings, where a difference is better shown whole.
    var limit: Int {
        switch self {
        case .fixtures: return 16
        case .recording(_, let limit): return limit
        }
    }

    /// Whether failure messages are kept (they only explain a difference).
    var keepsMessages: Bool {
        if case .recording = self { return true }
        return false
    }

    private func base(_ name: String, _ suffix: String) -> URL {
        switch self {
        case .fixtures: return TestPaths.fixtures.appendingPathComponent("\(name)\(suffix).tape")
        case .recording(let r, _): return TestPaths.expected.appendingPathComponent(r).appendingPathComponent("\(name)\(suffix).tape")
        }
    }

    /// The build configuration's suffix. GEOS's arcs (the buffer, the offset
    /// curve) take their points from the system's `sin` and `cos`, and an
    /// optimized build of GEOS gave other last bits than a debug build, as
    /// does the port, the same in each: GEOS's answers were stored from both
    /// builds, and an optimized build's tape is kept apart (`.release`)
    /// where it differs from the debug build's.
    static var configuration: String {
        #if DEBUG
        return ""
        #else
        return ".release"
        #endif
    }

    /// The tape a test reads: its build configuration's, else the debug build's.
    func url(_ name: String) -> URL {
        let variant = base(name, TapeStore.configuration)
        return FileManager.default.fileExists(atPath: variant.path) ? variant : base(name, "")
    }
}

/// Makes the oracle of a test: GEOS's answers as stored. They were written
/// at commit 18f264d, the last with GEOS in the package, by the same tests
/// asking GEOS itself (`TOPOLOGY_FREEZE=1`, its live oracle), and cannot be
/// made again. A test that asks another test's questions reads its tape.
enum Oracles {
    static func make(_ name: String, _ store: TapeStore = .fixtures) -> StoredOracle { FrozenOracle(name, store) }
}

/// One question to GEOS, as the alignment digest takes it: an operation's
/// number, its parameters and the digests of its inputs. The live and the
/// frozen oracle both fold each question in before its answer.
enum Question {
    case geometry(GeometryOp, [OracleInput])
    case predicate(PredicateOp, [OracleInput])
    case measure(MeasureOp, [OracleInput])
    case bounds(OracleInput)
    case nearestPoints(OracleInput, OracleInput)
    case validity(OracleInput)
    case relate(OracleInput, OracleInput)
    case orientationIndex(Coordinate, Coordinate, Coordinate)
    case isCCW([Double])
    case segmentIntersection(Coordinate, Coordinate, Coordinate, Coordinate)
    case wkt(OracleInput)
    case tree([OracleInput])
    case query(OracleInput)
    case nearest(OracleInput)
    case prepare(OracleInput)
    case prepared(PredicateOp, OracleInput)
    case project(OracleInput, OracleInput)
    case read(OracleInput)
    case linework([Shape])
    case jtsCase(String, Int)
    case jtsEvaluate(Int, String)
    case jtsRead(String, Double?)

    func align(_ d: inout Digest) {
        func inputs(_ code: Int, _ i: [OracleInput]) {
            d.add(code)
            for x in i { x.align(&d) }
        }
        func points(_ code: Int, _ p: [Coordinate]) {
            d.add(code)
            for c in p { d.add(c.x); d.add(c.y) }
        }
        switch self {
        case .geometry(let op, let i): inputs(100, i); op.align(&d)
        case .predicate(let op, let i): inputs(200 + op.code, i)
        case .measure(let op, let i): inputs(300 + op.rawValue, i)
        case .bounds(let i): inputs(400, [i])
        case .nearestPoints(let a, let b): inputs(401, [a, b])
        case .validity(let i): inputs(402, [i])
        case .relate(let a, let b): inputs(403, [a, b])
        case .orientationIndex(let a, let b, let c): points(404, [a, b, c])
        case .isCCW(let ring): d.add(405); for v in ring { d.add(v) }
        case .segmentIntersection(let p1, let p2, let q1, let q2): points(406, [p1, p2, q1, q2])
        case .wkt(let i): inputs(407, [i])
        case .tree(let items): inputs(408, items)
        case .query(let q): inputs(409, [q])
        case .nearest(let q): inputs(410, [q])
        case .prepare(let i): inputs(411, [i])
        case .prepared(let op, let q): inputs(412 + op.code, [q])
        case .project(let a, let b): inputs(430, [a, b])
        case .read(let i): inputs(431, [i])
        case .linework(let parts): inputs(432, parts.map { .shape($0) })
        case .jtsCase(let file, let index): d.add(440); d.add(file); d.add(index)
        case .jtsEvaluate(let index, let op): d.add(441); d.add(index); d.add(op)
        case .jtsRead(let text, let scale): d.add(442); d.add(text); d.add(scale ?? 0)
        }
    }
}

/// The stored answers of one test, read in order.
final class FrozenOracle: StoredOracle {
    let name: String
    let tape: TapeReader?
    /// The first problem with the tape (missing, out of step), reported once.
    private var problem: String?

    init(_ name: String, _ store: TapeStore) {
        self.name = name
        let url = store.url(name)
        do {
            tape = try TapeReader(url: url)
        } catch {
            tape = nil
            problem = "no stored GEOS answers for \(name) at \(url.path): \(error)"
        }
    }

    /// Reads the answer of the next question, or a placeholder once the
    /// tape is in trouble (which fails the test at its end).
    private func next<T>(_ fallback: T, _ q: Question, _ read: (TapeReader) throws -> T) -> T {
        guard let tape, problem == nil else { return fallback }
        q.align(&tape.alignment)
        do { return try read(tape) } catch {
            problem = "\(name): the tape is out of step at entry \(tape.entries): \(error)"
            return fallback
        }
    }

    func geometry(_ op: GeometryOp, _ inputs: [OracleInput], again: Bool) -> GeometryAnswer {
        next(.failure("no answer"), .geometry(op, inputs)) { try $0.geometry() }
    }

    func predicate(_ op: PredicateOp, _ inputs: [OracleInput]) -> Bool? {
        next(nil, .predicate(op, inputs)) { try $0.bool() }
    }

    func measure(_ op: MeasureOp, _ inputs: [OracleInput]) -> Double? {
        next(.nan, .measure(op, inputs)) { try $0.double() }
    }

    func bounds(_ input: OracleInput) -> StoredBytes {
        next(.whole([]), .bounds(input)) { try $0.doubles() ?? .whole([]) }
    }

    func nearestPoints(_ a: OracleInput, _ b: OracleInput) -> StoredBytes? {
        next(.whole([]), .nearestPoints(a, b)) { try $0.doubles() }
    }

    func validity(_ input: OracleInput) -> Verdict? {
        next(Verdict(valid: false, reason: "no answer", location: []), .validity(input)) { t in
            switch try t.tag() {
            case .none: return nil
            case .trueValue: return Verdict(valid: true, reason: "", location: [])
            case .falseValue:
                let reason = try t.rawString()
                let x = try t.raw { try $0.u64() }, y = try t.raw { try $0.u64() }
                return Verdict(valid: false, reason: reason, location: [x, y])
            case let other: throw TapeError("expected a verdict, found \(other)")
            }
        }
    }

    func relate(_ a: OracleInput, _ b: OracleInput) -> Result<String, OracleFailure> {
        next(.failure(OracleFailure(message: "no answer")), .relate(a, b)) { t in
            switch try t.tag() {
            case .failure: return .failure(OracleFailure(message: try t.failureMessage()))
            case let s where s == .stringRef || s == .stringNew: return .success(try t.rawString(after: s))
            case let other: throw TapeError("expected a matrix, found \(other)")
            }
        }
    }

    func orientationIndex(_ a: Coordinate, _ b: Coordinate, _ c: Coordinate) -> Int {
        next(-9, .orientationIndex(a, b, c)) { try $0.int() ?? -9 }
    }

    func isCCW(_ ring: [Double]) -> Bool {
        next(false, .isCCW(ring)) { try $0.bool() ?? false }
    }

    func segmentIntersection(_ p1: Coordinate, _ p2: Coordinate, _ q1: Coordinate, _ q2: Coordinate) -> SegmentAnswer {
        next(SegmentAnswer(result: -9, point: nil), .segmentIntersection(p1, p2, q1, q2)) { t in
            let r = try t.int() ?? -9
            return SegmentAnswer(result: r, point: r == 1 ? try t.doubles() : nil)
        }
    }

    func wkt(_ input: OracleInput) -> StoredBytes {
        next(.whole([]), .wkt(input)) { try $0.text() ?? .whole([]) }
    }

    func tree(_ items: [OracleInput]) -> Int {
        next(0, .tree(items)) { _ in 0 }
    }

    func query(_ tree: Int, _ q: OracleInput) -> StoredBytes {
        next(.whole([]), .query(q)) { try $0.ints() ?? .whole([]) }
    }

    func nearest(_ tree: Int, _ q: OracleInput) -> Int? {
        next(-1, .nearest(q)) { try $0.int() }
    }

    func prepare(_ input: OracleInput) -> Int {
        next(0, .prepare(input)) { _ in 0 }
    }

    func prepared(_ op: PredicateOp, _ handle: Int, _ q: OracleInput) -> Bool? {
        next(nil, .prepared(op, q)) { try $0.bool() }
    }

    func project(_ line: OracleInput, _ point: OracleInput) -> Double {
        next(.nan, .project(line, point)) { try $0.double() ?? .nan }
    }

    func read(_ input: OracleInput) -> GeometryAnswer {
        next(.failure("no answer"), .read(input)) { try $0.geometry() }
    }

    func linework(_ parts: [Shape], made: Shape?) {
        let stored = next(StoredBytes?.none, .linework(parts)) { try $0.ints() }
        guard problem == nil else { return }
        if made.map(TapeWriter.made) != stored {
            problem = "\(name): the linework made with the port differs from GEOS's at entry \(tape?.entries ?? 0): \(made.map { "\($0)" } ?? "fails")"
        }
    }

    func jtsCase(_ file: JTSTestFile, _ c: JTSTestFile.Case) -> (a: Bool, b: Bool) {
        next((false, false), .jtsCase(file.name, c.index)) { t in (try t.bool() ?? false, try t.bool() ?? false) }
    }

    func jtsEvaluate(_ file: JTSTestFile, _ test: JTSTestFile.Test) -> JTSAnswer {
        next(.none, .jtsEvaluate(test.index, test.operation)) { t in
            switch try t.tag() {
            case .none: return .none
            case .falseValue: return .boolean(false)
            case .trueValue: return .boolean(true)
            case .double: return .number(try t.raw { try $0.f64() })
            case .failure: return .geometry(.failure(try t.failureMessage()))
            case .geometry: return .geometry(.result(try t.raw { try StoredGeometry.read(&$0) }))
            case let other: throw TapeError("expected a JTS answer, found \(other)")
            }
        }
    }

    func jtsRead(_ text: String, scale: Double?) -> GeometryAnswer {
        next(.failure("no answer"), .jtsRead(text, scale)) { try $0.geometry() }
    }

    func finish(sourceLocation: SourceLocation) {
        if problem == nil, let tape {
            do { try tape.close() } catch { problem = "\(name): \(error)" }
        }
        if let problem { Issue.record(Comment(rawValue: problem), sourceLocation: sourceLocation) }
    }
}
