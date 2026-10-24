import Foundation
import Testing
import Topology
import geos

/// The JTS XML suites on the port, for the operations it has
/// (`TopologyEngine.supported`): it passes exactly the tests GEOS passes
/// (`GEOSBaseline`), its results are GEOS's bit for bit, and it reads every
/// input geometry of the suites as GEOS reads it.
@Suite struct JTSXMLTopologyTests {
    static func files() throws -> [JTSTestFile] {
        try TestPaths.suites.flatMap { TestPaths.xmlFiles($0) }.map { try JTSTestFile(url: $0) }
    }

    @Test func portPassesWhatGEOSPasses() throws {
        let runner = JTSTestRunner(engine: TopologyEngine())
        // The one input GEOS cannot read but JTS can (a WKT with text after the
        // geometry): the port reads it as JTS, and passes where GEOS errs.
        let jtsReadsGEOSRefuses: Set<String> = ["general/TestCentroid.xml#10.1"]
        let geosFails = Set(GEOSBaseline.notPassed).subtracting(jtsReadsGEOSRefuses)
        var counts: [String: (run: Int, passed: Int)] = [:]
        for file in try JTSXMLTopologyTests.files() {
            for r in runner.run(file) where r.outcome != .unsupported {
                let op = r.operation.lowercased()
                let passed = r.outcome == .passed
                counts[op, default: (0, 0)].run += 1
                if passed { counts[op]!.passed += 1 }
                if passed == geosFails.contains(r.id) {
                    Issue.record("\(r.id) \(r.operation): the port \(passed ? "passes" : "does not pass (\(r.outcome))") where GEOS \(passed ? "does not" : "does")")
                }
            }
        }
        for (op, c) in counts.sorted(by: { $0.key < $1.key }) { print("jts-xml \(op): run \(c.run), passed \(c.passed)") }
        #expect(!counts.isEmpty)
    }

    @Test func portResultsAreGEOSs() throws {
        let o = GEOSOracle()
        let port = TopologyEngine(), geos = GEOSEngine(oracle: o)
        var tally = ParityTally("JTS XML results")
        for file in try JTSXMLTopologyTests.files() {
            for c in file.cases {
                guard let pa = try? c.a.map({ try port.read($0, scale: file.fixedScale) }),
                      let ga = try? c.a.map({ try geos.read($0, scale: file.fixedScale) }) else { continue }
                let pb = try? c.b.map { try port.read($0, scale: file.fixedScale) }
                let gb = try? c.b.map { try geos.read($0, scale: file.fixedScale) }
                for t in c.tests where TopologyEngine.supported.contains(t.operation.lowercased()) {
                    let pt = t.target.uppercased() == "B" ? pb ?? nil : pa, gt = t.target.uppercased() == "B" ? gb ?? nil : ga
                    guard let pt, let gt else { continue }
                    let mine = try? port.evaluate(t, target: pt, a: pa, b: pb ?? nil, file: file)
                    let theirs = try? geos.evaluate(t, target: gt, a: ga, b: gb ?? nil, file: file)
                    let id = "\(file.name)#\(c.index).\(t.index) \(t.operation)"
                    switch (mine, theirs) {
                    case (.geometry(let m)?, .geometry(let g)?):
                        let (x, y) = o.normalizedShapes(m, g)
                        tally.check(x == y, "\(id): port \(x) GEOS \(y)")
                    case (.boolean(let m)?, .boolean(let g)?):
                        tally.check(m == g, "\(id): port \(m) GEOS \(g)")
                    case (nil, nil):
                        tally.check(true, "")
                    default:
                        tally.check(false, "\(id): port \(String(describing: mine)) GEOS \(String(describing: theirs))")
                    }
                }
            }
        }
        tally.report()
    }

    @Test func portReadsTheInputsAsGEOS() throws {
        let o = GEOSOracle()
        var tally = ParityTally("WKT and WKB reading (JTS XML inputs)")
        for file in try JTSXMLTopologyTests.files() {
            let port = TopologyEngine(), geos = GEOSEngine(oracle: o)
            for c in file.cases {
                for text in [c.a, c.b].compactMap({ $0 }) {
                    let g = try? geos.read(text, scale: file.fixedScale)
                    let p = try? port.read(text, scale: file.fixedScale)
                    // GEOS refuses text after the geometry, JTS reads it (TestCentroid 10).
                    if g == nil && p != nil && text.filter({ $0 == ")" }).count > text.filter({ $0 == "(" }).count { continue }
                    switch (p, g) {
                    case (let p?, let g?): tally.check(Shape(p) == g.shape, "\(file.name)#\(c.index): \(Shape(p)) vs \(g.shape)")
                    case (nil, nil): tally.check(true, "")
                    default: tally.check(false, "\(file.name)#\(c.index): port \(p.map { "\($0)" } ?? "fails") GEOS \(g.map { $0.wkt } ?? "fails")")
                    }
                }
            }
        }
        tally.report()
    }
}
