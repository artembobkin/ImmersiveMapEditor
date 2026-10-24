import Foundation
import Testing

/// The comparisons of one function with GEOS: how many, how many equal, and
/// the first differences, each with its input. Reports into the test's
/// output (the numbers `Docs/PortingParity.md` keeps) and fails the test on
/// any difference. With `PARITY_DUMP=<file>` every difference is also
/// appended to that file in full, to study it.
struct ParityTally {
    let name: String
    var compared = 0
    var differences = 0
    var examples: [String] = []

    init(_ name: String) { self.name = name }

    mutating func check(_ equal: Bool, _ detail: @autoclosure () -> String) {
        compared += 1
        if !equal {
            differences += 1
            let d = detail()
            if examples.count < 5 { examples.append(d) }
            ParityTally.dump("\(name): \(d)")
        }
    }

    static func dump(_ text: String) {
        guard let path = ProcessInfo.processInfo.environment["PARITY_DUMP"] else { return }
        let line = Data((text + "\n").utf8)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line)
            h.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line)
        }
    }

    /// Prints the line `name: compared N, equal M` and records each example
    /// difference as a test issue.
    func report(sourceLocation: SourceLocation = #_sourceLocation) {
        print("parity \(name): compared \(compared), equal \(compared - differences)")
        for e in examples { Issue.record("\(name) differs from GEOS: \(e.prefix(1500))", sourceLocation: sourceLocation) }
    }
}
