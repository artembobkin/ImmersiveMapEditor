import Foundation
import Testing

/// The comparisons of one function with GEOS: how many, how many equal, and
/// the first differences, each with its input. Reports into the test's
/// output (the numbers `Docs/PortingParity.md` keeps) and fails the test on
/// any difference.
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
            if examples.count < 5 { examples.append(detail()) }
        }
    }

    /// Prints the line `name: compared N, equal M` and records each example
    /// difference as a test issue.
    func report(sourceLocation: SourceLocation = #_sourceLocation) {
        print("parity \(name): compared \(compared), equal \(compared - differences)")
        for e in examples { Issue.record("\(name) differs from GEOS: \(e)", sourceLocation: sourceLocation) }
    }
}
