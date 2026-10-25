import Foundation
import Testing
import Topology

/// The JTS XML suites on the port, for the operations it has
/// (`TopologyEngine.supported`): it passes exactly the tests GEOS 3.13
/// passed (`GEOSBaseline`), its results are GEOS's bit for bit (GEOS's
/// stored answers), and it reads every input geometry of the suites as GEOS
/// read it. The suites stay outside git (`.build/ports/jts`); GEOS's answers
/// on them are in git (`.oracle`).
@Suite struct JTSXMLTopologyTests {
    static func files() throws -> [JTSTestFile] {
        try TestPaths.suites.flatMap { TestPaths.xmlFiles($0) }.map { try JTSTestFile(url: $0) }
    }

    @Test func theSuitesAreThere() {
        #expect(TestPaths.jts != nil, "JTS 1.20.0 is not at .build/ports/jts (or JTS_ROOT)")
        for suite in TestPaths.suites { #expect(!TestPaths.xmlFiles(suite).isEmpty, "no XML files in \(suite)") }
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
        let o = Oracles.make("JTSXMLTopologyTests.portResultsAreGEOSs")
        defer { o.finish() }
        let port = TopologyEngine()
        var tally = ParityTally("JTS XML results")
        for file in try JTSXMLTopologyTests.files() {
            for c in file.cases {
                // Whether GEOS read the inputs (true when there is none).
                let geos = o.jtsCase(file, c)
                guard let pa = try? c.a.map({ try port.read($0, scale: file.fixedScale) }), geos.a else { continue }
                let pb = try? c.b.map { try port.read($0, scale: file.fixedScale) }
                let hasB = geos.b && c.b != nil
                for t in c.tests where TopologyEngine.supported.contains(t.operation.lowercased()) {
                    let isB = t.target.uppercased() == "B"
                    let pt = isB ? pb ?? nil : pa, gt = isB ? hasB : c.a != nil
                    guard let pt, gt else { continue }
                    let mine = try? port.evaluate(t, target: pt, a: pa, b: pb ?? nil, file: file)
                    let theirs = o.jtsEvaluate(file, t)
                    let id = "\(file.name)#\(c.index).\(t.index) \(t.operation)"
                    switch (mine, theirs) {
                    case (.geometry(let m)?, .geometry(.result(let g))):
                        tally.check(g.compare(raw: Shape(m), normal: Shape(m.norm())) == .equal, "\(id): port \(Shape(m.norm())) GEOS \(g.normalDescription)")
                    case (.boolean(let m)?, .boolean(let g)):
                        tally.check(m == g, "\(id): port \(m) GEOS \(g)")
                    case (.number(let m)?, .number(let g)):
                        tally.check(m.bitPattern == g.bitPattern, "\(id): port \(m) GEOS \(g)")
                    case (nil, .none):
                        tally.check(true, "")
                    default:
                        tally.check(false, "\(id): port \(String(describing: mine)) GEOS \(theirs)")
                    }
                }
            }
        }
        tally.report()
    }

    @Test func portReadsTheInputsAsGEOS() throws {
        let o = Oracles.make("JTSXMLTopologyTests.portReadsTheInputsAsGEOS")
        defer { o.finish() }
        var tally = ParityTally("WKT and WKB reading (JTS XML inputs)")
        for file in try JTSXMLTopologyTests.files() {
            let port = TopologyEngine()
            for c in file.cases {
                for text in [c.a, c.b].compactMap({ $0 }) {
                    let g = o.jtsRead(text, scale: file.fixedScale)
                    let p = try? port.read(text, scale: file.fixedScale)
                    // GEOS refuses text after the geometry, JTS reads it (TestCentroid 10).
                    if case .failure = g, p != nil, text.filter({ $0 == ")" }).count > text.filter({ $0 == "(" }).count { continue }
                    switch (p, g) {
                    case (let p?, .result(let g)): tally.check(g.rawEquals(Shape(p)), "\(file.name)#\(c.index): \(Shape(p)) vs \(g.description)")
                    case (nil, .failure): tally.check(true, "")
                    default: tally.check(false, "\(file.name)#\(c.index): port \(p.map { "\($0)" } ?? "fails") GEOS \(g.result?.description ?? "fails")")
                    }
                }
            }
        }
        tally.report()
    }
}
