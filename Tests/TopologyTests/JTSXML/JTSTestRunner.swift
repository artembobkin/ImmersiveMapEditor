import Foundation

/// The kind of result a JTS test operation gives, by its name, as JTS's
/// `GeometryMethodOperation` and `TestCaseGeometryFunctions` return it.
enum JTSResultKind {
    case geometry, boolean, number

    init(operation: String) {
        switch operation.lowercased() {
        case "isvalid", "issimple", "intersects", "contains", "covers", "coveredby", "within", "touches", "overlaps",
             "equalstopo", "disjoint", "crosses", "relate", "iswithindistance", "equalsexact", "equalsnorm",
             "overlayareatest", "containsproperly":
            self = .boolean
        case "distance", "minclearance", "unionarea", "unionlength", "getarea", "getlength":
            self = .number
        default:
            self = .geometry
        }
    }
}

/// A test's result as an engine computes it.
enum JTSValue<G> {
    case geometry(G)
    case boolean(Bool)
    case number(Double)
}

/// What a test came to.
enum JTSOutcome: Equatable {
    case passed
    case failed(String)
    /// The engine threw (GEOS failed, an input could not be read).
    case error(String)
    /// The engine does not have the operation (not ported yet).
    case unsupported
}

/// An implementation the JTS XML tests run on: the port (GEOS was one, as the
/// oracle, until phase 12).
protocol JTSTestEngine {
    associatedtype G
    /// Reads a geometry of a test, its coordinates made precise to `scale`
    /// when the file's precision model is fixed.
    func read(_ wkt: String, scale: Double?) throws -> G
    /// The operation of a test, nil when the engine does not have it.
    func evaluate(_ test: JTSTestFile.Test, target: G, a: G?, b: G?, file: JTSTestFile) throws -> JTSValue<G>?
    /// Whether two geometry results are equal: both normalized, then
    /// `equalsExact` within the tolerance (JTS's `GeometryResult.equals`).
    func equal(_ actual: G, _ expected: G, tolerance: Double) -> Bool
    /// JTS's `BufferResultMatcher`: the symmetric difference's area and the
    /// boundaries' Hausdorff distance within their bounds.
    func bufferMatch(_ actual: G, _ expected: G, distance: Double) -> Bool
    func describe(_ g: G) -> String
}

struct JTSEngineError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}

/// Runs JTS XML tests on an engine and keeps every outcome.
struct JTSTestRunner<E: JTSTestEngine> {
    let engine: E

    struct Record {
        /// `general/TestCentroid.xml#3.1`: the file, the case and the test.
        var id: String
        var operation: String
        var outcome: JTSOutcome
    }

    func run(_ file: JTSTestFile) -> [Record] {
        var records: [Record] = []
        for c in file.cases {
            var a: E.G?, b: E.G?
            var readError: String?
            do {
                a = try c.a.map { try engine.read($0, scale: file.fixedScale) }
                b = try c.b.map { try engine.read($0, scale: file.fixedScale) }
            } catch {
                readError = "\(error)"
            }
            for t in c.tests {
                let id = "\(file.name)#\(c.index).\(t.index)"
                let outcome: JTSOutcome
                if let readError {
                    outcome = .error("input: \(readError)")
                } else {
                    outcome = run(t, a: a, b: b, file: file)
                }
                records.append(Record(id: id, operation: t.operation, outcome: outcome))
            }
        }
        return records
    }

    func run(_ t: JTSTestFile.Test, a: E.G?, b: E.G?, file: JTSTestFile) -> JTSOutcome {
        guard let target = t.target.uppercased() == "B" ? b : a else { return .error("no geometry \(t.target)") }
        let actual: JTSValue<E.G>
        do {
            guard let v = try engine.evaluate(t, target: target, a: a, b: b, file: file) else { return .unsupported }
            actual = v
        } catch {
            return .error("\(error)")
        }
        guard let expected = t.expected else { return .passed }
        switch actual {
        case .boolean(let v):
            guard let e = Bool(expected.lowercased()) else { return .error("expected \(expected) is not a boolean") }
            return v == e ? .passed : .failed("\(v)")
        case .number(let v):
            guard let e = Double(expected) else { return .error("expected \(expected) is not a number") }
            return abs(v - e) <= file.tolerance ? .passed : .failed("\(v)")
        case .geometry(let g):
            let e: E.G
            do { e = try engine.read(expected, scale: file.fixedScale) } catch { return .error("expected: \(error)") }
            let isBuffer = t.operation.lowercased() == "buffer" && file.resultMatcher?.hasSuffix("BufferResultMatcher") == true
            if isBuffer, let d = t.arguments.first.flatMap(Double.init) {
                return engine.bufferMatch(g, e, distance: d) ? .passed : .failed(engine.describe(g))
            }
            return engine.equal(g, e, tolerance: file.tolerance) ? .passed : .failed(engine.describe(g))
        }
    }
}

