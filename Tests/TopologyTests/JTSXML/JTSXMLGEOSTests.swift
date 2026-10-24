import Foundation
import Testing

/// The JTS XML suites run on GEOS, to check the runner before it checks the
/// port: every file parses, and the tests GEOS does not pass are exactly the
/// ones `GEOSBaseline` lists (GEOS 3.13 differs from JTS 1.20 in places: its
/// overlay is OverlayNG where JTS's tests expect the old one, and the like).
///
/// `WRITE_GEOS_BASELINE=1 swift test --filter JTSXMLGEOSTests` writes the
/// baseline again from what GEOS does.
@Suite struct JTSXMLGEOSTests {
    @Test func theSuitesAreThere() {
        #expect(TestPaths.jts != nil, "JTS 1.20.0 is not at .build/ports/jts (or JTS_ROOT)")
        for suite in TestPaths.suites { #expect(!TestPaths.xmlFiles(suite).isEmpty, "no XML files in \(suite)") }
    }

    @Test func geosPassesWhatTheBaselineSays() throws {
        let engine = GEOSEngine(oracle: GEOSOracle())
        let runner = JTSTestRunner(engine: engine)
        var notPassed: [String: String] = [:]
        var lines: [String] = []
        for suite in TestPaths.suites {
            var total = (passed: 0, failed: 0, errors: 0, unsupported: 0)
            for url in TestPaths.xmlFiles(suite) {
                let file = try JTSTestFile(url: url)
                for r in runner.run(file) {
                    switch r.outcome {
                    case .passed: total.passed += 1
                    case .failed(let a): total.failed += 1; notPassed[r.id] = "failed: \(a.prefix(80))"
                    case .error(let e): total.errors += 1; notPassed[r.id] = "error: \(e.prefix(80))"
                    case .unsupported: total.unsupported += 1; notPassed[r.id] = "unsupported"
                    }
                }
            }
            lines.append("\(suite): \(total.passed) passed, \(total.failed) failed, \(total.errors) errors, \(total.unsupported) unsupported")
        }
        print(lines.joined(separator: "\n"))
        if ProcessInfo.processInfo.environment["WRITE_GEOS_BASELINE"] == "1" {
            try GEOSBaselineWriter.write(notPassed, summary: lines)
            return
        }
        let expected = Set(GEOSBaseline.notPassed)
        let actual = Set(notPassed.keys)
        for id in actual.subtracting(expected).sorted() { Issue.record("GEOS newly fails \(id): \(notPassed[id]!)") }
        for id in expected.subtracting(actual).sorted() { Issue.record("GEOS newly passes \(id)") }
        #expect(lines == GEOSBaseline.summary)
    }
}

/// Writes `GEOSBaseline.swift` from a run.
enum GEOSBaselineWriter {
    static func write(_ notPassed: [String: String], summary: [String]) throws {
        var s = """
        /// What GEOS 3.13 does on the JTS 1.20.0 XML suites, as `JTSXMLGEOSTests`
        /// found it (written by it with `WRITE_GEOS_BASELINE=1`): the count per
        /// suite and every test GEOS does not pass, with why.
        enum GEOSBaseline {
            static let summary = [

        """
        for l in summary { s += "        \"\(l)\",\n" }
        s += "    ]\n\n    static let notPassed = [\n"
        for id in notPassed.keys.sorted() {
            let why = notPassed[id]!.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\n", with: " ")
            s += "        \"\(id)\", // \(why)\n"
        }
        s += "    ]\n}\n"
        let url = TestPaths.package.appendingPathComponent("Tests/TopologyTests/JTSXML/GEOSBaseline.swift")
        try s.write(to: url, atomically: true, encoding: .utf8)
    }
}
